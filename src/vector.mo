import Principal "mo:base/Principal";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Node "mo:devefi/node";
import Tools "mo:neuro/tools";
import GovT "mo:neuro/interfaces/nns_interface";
import AccountIdentifier "mo:account-identifier";
import { NNS } "mo:neuro";
import Map "mo:map/Map";
import Vector "mo:vector/Class";
import T "./types";
import N "./neuron";

module {

    public class NeuronVector({
        node_fee : Nat;
        canister_id : Principal;
        icp_ledger : Principal;
        icp_governance : Principal;
    }) {

        let nns = NNS.Governance({
            canister_id = canister_id;
            nns_canister_id = icp_governance;
            icp_ledger_canister_id = icp_ledger;
        });

        // Caches are checked again after this time
        let TIMEOUT_NANOS : Nat64 = (5 * 60 * 1_000_000_000);

        // 1.06 ICP in e8s
        let MINIMUM_SPAWN : Nat64 = 106_000_000;

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L41
        let GOVERNANCE_TOPICS : [Int32] = [
            0, // Catch all, except Governance & SNS & Community Fund
            4, // Governance
            14, // SNS & Community Fund
        ];

        let NEURON_STATES = {
            locked : Int32 = 1;
            dissolving : Int32 = 2;
            unlocked : Int32 = 3;
            spawning : Int32 = 4;
        };

        public func sync_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : () {
            label vloop for ((vid, vec) in nodes.entries()) {
                if (not vec.active) continue vloop;
                if (not nodes.hasDestination(vec, 0)) continue vloop;
                let ?source = nodes.getSource(vid, vec, 0) else continue vloop;

                let bal = source.balance();
                let ledger_fee = source.fee();
                if (bal <= node_fee + ledger_fee) continue vloop;

                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(canister_id, Nat64.fromNat32(vid));
                        ignore source.send(#external_account({ owner = icp_governance; subaccount = ?neuronSubaccount }), bal - node_fee);
                        // TODO process neuron refreshes after send
                    };
                };
            };
        };

        public func async_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        if (not ready(nodeMem)) continue vloop;
                        try {
                            await* claim_neuron(nodeMem, vid);
                            await* update_delay(nodeMem);
                            await* update_followees(nodeMem);
                            await* update_dissolving(nodeMem);
                            await* disburse_neuron(nodeMem, vec.refund[0]);
                            await* spawn_maturity(nodeMem, vid);
                            await* claim_maturity(nodeMem, vec.destinations[0]);
                        } catch (error) {
                            // log error
                        } finally {
                            nodeMem.internals.updating := #Done(get_now_nanos());
                        };
                    };
                };
            };
        };

        public func refresh_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            let { full_neurons; neuron_infos } = await* nns.listNeurons({
                neuronIds = [];
                readable = true;
            });

            let neuronInfos = Map.fromIter<Nat64, GovT.NeuronInfo>(neuron_infos.vals(), Map.n64hash);

            let fullNeurons = Map.fromIterMap<Blob, GovT.Neuron, GovT.Neuron>(
                full_neurons.vals(),
                Map.bhash,
                func(neuron : GovT.Neuron) : ?(Blob, GovT.Neuron) {
                    return ?(Blob.fromArray(neuron.account), neuron);
                },
            );

            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        update_neuron_cache(nodeMem, neuronInfos, fullNeurons);
                        update_spawning_neurons_cache(nodeMem, vid, fullNeurons);
                    };
                };
            };
        };

        private func get_neuron_nonce(vid : Nat32, localId : Nat32) : Nat64 {
            return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
        };

        private func get_now_nanos() : Nat64 {
            return Time.now() |> Int.abs(_) |> Nat64.fromNat(_);
        };

        private func ready(nodeMem : N.Mem) : Bool {
            switch (nodeMem.internals.updating) {
                case (#Init) {
                    nodeMem.internals.updating := #Calling(get_now_nanos());
                    return true;
                };
                case (#Calling(ts) or #Done(ts)) {
                    if (get_now_nanos() >= ts + TIMEOUT_NANOS) {
                        nodeMem.internals.updating := #Calling(get_now_nanos());
                        return true;
                    } else {
                        return false;
                    };
                };
            };
        };

        private func update_neuron_cache(nodeMem : N.Mem, neuronInfos : Map.Map<Nat64, GovT.NeuronInfo>, fullNeurons : Map.Map<Blob, GovT.Neuron>) : () {
            let ?nid = nodeMem.cache.neuron_id else return;
            let ?nonce = nodeMem.cache.nonce else return;

            let neuronSub : Blob = Tools.computeNeuronStakingSubaccountBytes(canister_id, nonce);

            let ?info = Map.get(neuronInfos, Map.n64hash, nid) else return;
            let ?full = Map.get(fullNeurons, Map.bhash, neuronSub) else return;

            nodeMem.cache.maturity_e8s_equivalent := ?full.maturity_e8s_equivalent;
            nodeMem.cache.cached_neuron_stake_e8s := ?full.cached_neuron_stake_e8s;
            nodeMem.cache.created_timestamp_seconds := ?full.created_timestamp_seconds;
            nodeMem.cache.followees := full.followees;
            nodeMem.cache.dissolve_delay_seconds := ?info.dissolve_delay_seconds;
            nodeMem.cache.state := ?info.state;
            nodeMem.cache.voting_power := ?info.voting_power;
            nodeMem.cache.age_seconds := ?info.age_seconds;
        };

        private func update_spawning_neurons_cache(nodeMem : N.Mem, vid : Nat32, fullNeurons : Map.Map<Blob, GovT.Neuron>) : () {
            let spawningNeurons = Vector.Vector<N.SpawningNeuronCache>();

            var idx : Nat32 = 1;
            while (idx <= nodeMem.internals.local_idx) {
                let spawningSub : Blob = Tools.computeNeuronStakingSubaccountBytes(canister_id, get_neuron_nonce(vid, idx));
                let ?full = Map.get(fullNeurons, Map.bhash, spawningSub) else return;

                if (full.cached_neuron_stake_e8s > 0 or full.maturity_e8s_equivalent > 0) {
                    spawningNeurons.add({
                        var nonce = get_neuron_nonce(vid, idx);
                        var maturity_e8s_equivalent = full.maturity_e8s_equivalent;
                        var cached_neuron_stake_e8s = full.cached_neuron_stake_e8s;
                        var created_timestamp_seconds = full.created_timestamp_seconds;
                    });
                };

                idx += 1;
            };

            nodeMem.internals.spawning_neurons := Vector.toArray(spawningNeurons);
        };

        private func claim_neuron(nodeMem : N.Mem, vid : Nat32) : async* () {
            if (Option.isSome(nodeMem.cache.neuron_id)) return;
            let firstNonce = get_neuron_nonce(vid, 0);
            let #ok(neuronId) = await* nns.claimNeuron({ nonce = firstNonce }) else return;
            nodeMem.cache.neuron_id := ?neuronId;
            nodeMem.cache.nonce := ?firstNonce;
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?delaySeconds = nodeMem.init.delay_seconds else return;

            if (Option.isNull(nodeMem.cache.dissolve_delay_seconds)) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                let #ok(_) = await* neuron.setDissolveTimestamp({
                    dissolve_timestamp_seconds = get_now_nanos() + delaySeconds;
                }) else return;
            };
        };

        private func update_followees(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?followeeToSet = nodeMem.variables.update_followee else return;

            let currentFollowees = Map.fromIter<Int32, GovT.Followees>(nodeMem.cache.followees.vals(), Map.i32hash);

            label topicLoop for (topic in GOVERNANCE_TOPICS.vals()) {
                let needsUpdate = switch (Map.get(currentFollowees, Map.i32hash, topic)) {
                    case (?{ followees }) { followees[0].id != followeeToSet };
                    case _ { true };
                };

                if (needsUpdate) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = icp_governance;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    let #ok(_) = await* neuron.follow({
                        topic = topic;
                        followee = followeeToSet;
                    }) else continue topicLoop;
                };
            };
        };

        private func update_dissolving(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?updateDissolving = nodeMem.variables.update_dissolving else return;
            let ?dissolvingState = nodeMem.cache.state else return;

            if (updateDissolving and dissolvingState == NEURON_STATES.locked) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                let #ok(_) = await* neuron.startDissolving() else return;
            };

            if (not updateDissolving and dissolvingState == NEURON_STATES.dissolving) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                let #ok(_) = await* neuron.stopDissolving() else return;
            };
        };

        private func disburse_neuron(nodeMem : N.Mem, refund : Node.Endpoint) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?updateDissolving = nodeMem.variables.update_dissolving else return;
            let ?dissolvingState = nodeMem.cache.state else return;
            let ?cachedStake = nodeMem.cache.cached_neuron_stake_e8s else return;

            if (updateDissolving and dissolvingState == NEURON_STATES.unlocked and cachedStake >= 0) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                let #ic({ account }) = refund else return;

                let #ok(_) = await* neuron.disburse({
                    to_account = ?{
                        hash = AccountIdentifier.accountIdentifier(
                            account.owner,
                            Option.get(account.subaccount, AccountIdentifier.defaultSubaccount()),
                        ) |> Blob.toArray(_);
                    };
                    amount = null;
                }) else return;
            };
        };

        private func spawn_maturity(nodeMem : N.Mem, vid : Nat32) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?cachedMaturity = nodeMem.cache.maturity_e8s_equivalent else return;

            if (cachedMaturity > MINIMUM_SPAWN) {
                nodeMem.internals.local_idx += 1;
                let newNonce : Nat64 = get_neuron_nonce(vid, nodeMem.internals.local_idx);

                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                let #ok(_) = await* neuron.spawn({
                    nonce = ?newNonce;
                    new_controller = null;
                    percentage_to_spawn = null;
                }) else return;
            };
        };

        private func claim_maturity(nodeMem : N.Mem, destination : Node.DestinationEndpoint) : async* () {
            label spawnLoop for (spawningNeuron in nodeMem.internals.spawning_neurons.vals()) {
                if (spawningNeuron.cached_neuron_stake_e8s > 0) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = icp_governance;
                        neuron_id_or_subaccount = #Subaccount(
                            Blob.toArray(
                                Tools.computeNeuronStakingSubaccountBytes(canister_id, spawningNeuron.nonce)
                            )
                        );
                    });

                    let #ic({ account = ?account }) = destination else continue spawnLoop;

                    let #ok(_) = await* neuron.disburse({
                        to_account = ?{
                            hash = AccountIdentifier.accountIdentifier(
                                account.owner,
                                Option.get(account.subaccount, AccountIdentifier.defaultSubaccount()),
                            ) |> Blob.toArray(_);
                        };
                        amount = null;
                    }) else continue spawnLoop;
                };
            };
        };

    };
};
