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
        let TIMEOUT_NANOS : Nat64 = (3 * 60 * 1_000_000_000);

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
                if (not nodes.hasDestination(vec, 0)) continue vloop;
                let ?source = nodes.getSource(vec, 0) else continue vloop;

                let bal = source.balance();
                let ledger_fee = source.fee();
                if (bal <= node_fee + ledger_fee) continue vloop;

                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(canister_id, Nat64.fromNat32(vid));
                        source.send(#external_account({ owner = icp_governance; subaccount = ?neuronSubaccount }), bal - node_fee);
                        // TODO process neuron refreshes 60 seconds after send
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
                            await* claim_neuron(nodeMem, Nat64.fromNat32(vid));
                            await* update_delay(nodeMem);
                            await* update_followees(nodeMem);
                            await* update_dissolving(nodeMem);
                            await* disburse_neuron(nodeMem, vec.refund[0]);
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
                neuronIds = []; // TODO batch with 100 neurons at a time
                readable = true;
            });

            let neuronInfos = Map.fromIter<Nat64, GovT.NeuronInfo>(neuron_infos.vals(), Map.n64hash);

            let fullNeurons = Map.fromIterMap<Nat64, GovT.Neuron, GovT.Neuron>(
                full_neurons.vals(),
                Map.n64hash,
                func(neuron : GovT.Neuron) : ?(Nat64, GovT.Neuron) {
                    let ?{ id } = neuron.id else return null;
                    return ?(id, neuron);
                },
            );

            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        let ?nid = nodeMem.cache.neuron_id else continue vloop;
                        let ?nInfo = Map.get(neuronInfos, Map.n64hash, nid) else continue vloop;
                        let ?nFull = Map.get(fullNeurons, Map.n64hash, nid) else continue vloop;

                        nodeMem.cache.maturity_e8s_equivalent := ?nFull.maturity_e8s_equivalent;
                        nodeMem.cache.cached_neuron_stake_e8s := ?nFull.cached_neuron_stake_e8s;
                        nodeMem.cache.created_timestamp_seconds := ?nFull.created_timestamp_seconds;
                        nodeMem.cache.followees := nFull.followees;
                        nodeMem.cache.dissolve_delay_seconds := ?nInfo.dissolve_delay_seconds;
                        nodeMem.cache.state := ?nInfo.state;
                        nodeMem.cache.voting_power := ?nInfo.voting_power;
                        nodeMem.cache.age_seconds := ?nInfo.age_seconds;
                    };
                };
            };
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

        private func claim_neuron(nodeMem : N.Mem, nonce : Nat64) : async* () {
            if (Option.isSome(nodeMem.cache.neuron_id)) return;
            let #ok(neuronId) = await* nns.claimNeuron({ nonce = nonce }) else return;
            nodeMem.cache.neuron_id := ?neuronId;
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?delaySeconds = nodeMem.init.delay_seconds else return;

            if (Option.isNull(nodeMem.cache.dissolve_delay_seconds)) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id = neuron_id;
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
                        neuron_id = neuron_id;
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
                    neuron_id = neuron_id;
                });

                let #ok(_) = await* neuron.startDissolving() else return;
            };

            if (not updateDissolving and dissolvingState == NEURON_STATES.dissolving) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id = neuron_id;
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
                    neuron_id = neuron_id;
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

        // TODO spawn maturity if enough maturity

        // TODO claim maturity if ready
    };
};
