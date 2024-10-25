import Principal "mo:base/Principal";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Node "mo:devefi/node";
import DeVeFi "mo:devefi";
import Tools "mo:neuro/tools";
import GovT "mo:neuro/interfaces/nns_interface";
import { NNS } "mo:neuro";
import Map "mo:map/Map";
import Vector "mo:vector/Class";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import AI "mo:account-identifier";
import T "./types";
import N "./neuron";
import U "./utils";

module {

    public class NeuronVector({
        canister_id : Principal;
        icp_ledger : Principal;
        icp_ledger_cls : DeVeFi.LedgerCls;
        icp_governance : Principal;
    }) {

        let nns = NNS.Governance({
            canister_id = canister_id;
            nns_canister_id = icp_governance;
            icp_ledger_canister_id = icp_ledger;
        });

        // Caches are checked again after this time
        let TIMEOUT_NANOS : Nat64 = (6 * 60 * 1_000_000_000);

        // 1.06 ICP in e8s
        let MINIMUM_SPAWN : Nat64 = 106_000_000;

        // Maximum number of activities to keep in the main neuron's activity log
        let ACTIVITY_LOG_LIMIT : Nat = 10;

        // Minimum allowable delay increase, defined as a buffer of two weeks (in seconds)
        let DELAY_BUFFER_SECONDS : Nat64 = (14 * 24 * 60 * 60);

        // From here: https://github.com/dfinity/ic/blob/master/rs/nervous_system/common/src/lib.rs#L67C15-L67C27
        let ONE_YEAR_SECONDS : Nat64 = (4 * 365 + 1) * (24 * 60 * 60) / 4;

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/src/governance.rs#L164
        let MAXIMUM_DELAY_SECONDS : Nat64 = 8 * ONE_YEAR_SECONDS;

        // From here: https://github.com/dfinity/ic/blob/master/rs/sns/governance/src/neuron.rs#L22
        let MAX_LIST_NEURON_RESULT : Nat = 100;

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L41
        let GOVERNANCE_TOPICS : [Int32] = [
            0, // Catch all, except Governance & SNS & Community Fund
            4, // Governance
            14, // SNS & Community Fund
        ];

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L149
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
                if (source.balance() <= source.fee()) continue vloop;

                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(canister_id, U.get_neuron_nonce(vid, 0));

                        let #ok(txId) = source.send(#external_account({ owner = icp_governance; subaccount = ?neuronSubaccount }), source.balance()) else continue vloop;
                        // if a neuron exists, we refresh
                        if (Option.isSome(nodeMem.cache.neuron_id)) {
                            let txs = Vector.fromArray<Nat64>(nodeMem.internals.refresh_idx);
                            txs.add(txId);
                            nodeMem.internals.refresh_idx := Vector.toArray(txs);
                        };
                    };
                };
            };
        };

        public func async_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            label vloop for ((vid, vec) in nodes.entries()) {
                if (not vec.active) continue vloop;
                if (not nodes.hasDestination(vec, 0)) continue vloop;

                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        if (not ready(nodeMem)) continue vloop;
                        try {
                            await* claim_neuron(nodeMem, vid);
                            await* refresh_neuron(nodeMem);
                            await* update_delay(nodeMem);
                            await* update_followees(nodeMem);
                            await* update_dissolving(nodeMem);
                            await* disburse_neuron(nodeMem, vec.refund);
                            await* spawn_maturity(nodeMem, vid);
                            await* claim_maturity(nodeMem, vec.destinations[0]);
                        } catch (err) {
                            log_activity(nodeMem, "async_cycle", #Err(Error.message(err)));
                        } finally {
                            nodeMem.internals.updating := #Done(U.get_now_nanos());
                        };
                    };
                };
            };
        };

        public func cache_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            // Fetch all neuron IDs
            let neuron_ids = await* nns.getNeuronIds();

            // Process neuron IDs in batches of 100
            var startIndex : Nat = 0;
            while (startIndex < neuron_ids.size()) {
                let remainingNeurons : Nat = neuron_ids.size() - startIndex;

                let current_batch_size = Nat.min(remainingNeurons, MAX_LIST_NEURON_RESULT);

                let batch = Array.subArray(neuron_ids, startIndex, current_batch_size);

                await* process_neuron_batch(batch, nodes);

                startIndex += current_batch_size;
            };
        };

        private func process_neuron_batch(neuron_ids : [Nat64], nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            let { full_neurons; neuron_infos } = await* nns.listNeurons({
                neuronIds = neuron_ids;
                readable = false;
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

            // finds neurons that this vector owner has created and adds them to the cache
            // start at 1, 0 is reserved for the vectors main neuron
            var idx : Nat32 = 1;
            label idxLoop while (idx <= nodeMem.internals.local_idx) {
                let spawningNonce : Nat64 = U.get_neuron_nonce(vid, idx);
                let spawningSub : Blob = Tools.computeNeuronStakingSubaccountBytes(canister_id, spawningNonce);
                let ?full = Map.get(fullNeurons, Map.bhash, spawningSub) else continue idxLoop;

                // adds spawning neurons too, a possible memory adjustment could be to just add spawned neurons,
                // it is nice to show the vector owner the neurons that are spawning though
                if (full.cached_neuron_stake_e8s > 0 or full.maturity_e8s_equivalent > 0) {
                    spawningNeurons.add({
                        var nonce = spawningNonce;
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
            let firstNonce = U.get_neuron_nonce(vid, 0); // first localIdx for every neuron is always 0
            switch (await* nns.claimNeuron({ nonce = firstNonce })) {
                case (#ok(neuronId)) {
                    nodeMem.cache.neuron_id := ?neuronId;
                    nodeMem.cache.nonce := ?firstNonce;

                    log_activity(nodeMem, "claim_neuron", #Ok);
                };
                case (#err(err)) {
                    log_activity(nodeMem, "claim_neuron", #Err(debug_show err));
                };
            };
        };

        private func refresh_neuron(nodeMem : N.Mem) : async* () {
            let { cls = #icp(ledger) } = icp_ledger_cls else return;
            let ?firstNonce = nodeMem.cache.nonce else return;

            label refreshLoop for (idx in nodeMem.internals.refresh_idx.vals()) {
                if (ledger.isSent(idx)) {
                    switch (await* nns.claimNeuron({ nonce = firstNonce })) {
                        case (#ok(_)) {
                            nodeMem.internals.refresh_idx := Array.filter<Nat64>(
                                nodeMem.internals.refresh_idx,
                                func(x : Nat64) : Bool { x != idx },
                            );

                            log_activity(nodeMem, "refresh_neuron", #Ok);
                        };
                        case (#err(err)) {
                            log_activity(nodeMem, "refresh_neuron", #Err(debug_show err));
                        };
                    };
                };
            };
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?cachedDelay = nodeMem.cache.dissolve_delay_seconds else return;
            let delayToSet = nodeMem.variables.update_delay_seconds;

            if (delayToSet > cachedDelay + DELAY_BUFFER_SECONDS and delayToSet <= MAXIMUM_DELAY_SECONDS) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = (U.get_now_nanos() / 1_000_000_000) + delayToSet })) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "update_delay", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "update_delay", #Err(debug_show err));
                    };
                };
            };
        };

        private func update_followees(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let followeeToSet = nodeMem.variables.update_followee;

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

                    switch (await* neuron.follow({ topic = topic; followee = followeeToSet })) {
                        case (#ok(_)) {
                            log_activity(nodeMem, "update_followees", #Ok);
                        };
                        case (#err(err)) {
                            log_activity(nodeMem, "update_followees", #Err(debug_show err));
                        };
                    };
                };
            };
        };

        private func update_dissolving(nodeMem : N.Mem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?dissolvingState = nodeMem.cache.state else return;
            let updateDissolving = nodeMem.variables.update_dissolving;

            if (updateDissolving and dissolvingState == NEURON_STATES.locked) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.startDissolving()) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "start_dissolving", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "start_dissolving", #Err(debug_show err));
                    };
                };
            };

            if (not updateDissolving and dissolvingState == NEURON_STATES.dissolving) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.stopDissolving()) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "stop_dissolving", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "stop_dissolving", #Err(debug_show err));
                    };
                };
            };
        };

        private func disburse_neuron(nodeMem : N.Mem, refund : Node.Account) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?dissolvingState = nodeMem.cache.state else return;
            let ?cachedStake = nodeMem.cache.cached_neuron_stake_e8s else return;
            let updateDissolving = nodeMem.variables.update_dissolving;

            if (updateDissolving and dissolvingState == NEURON_STATES.unlocked and cachedStake > 0) {
                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.disburse({ to_account = ?{ hash = AI.accountIdentifier(refund.owner, Option.get(refund.subaccount, AI.defaultSubaccount())) |> Blob.toArray(_) }; amount = null })) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "disburse_neuron", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "disburse_neuron", #Err(debug_show err));
                    };
                };
            };
        };

        private func spawn_maturity(nodeMem : N.Mem, vid : Nat32) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?cachedMaturity = nodeMem.cache.maturity_e8s_equivalent else return;

            if (cachedMaturity > MINIMUM_SPAWN) {
                nodeMem.internals.local_idx += 1;
                let newNonce : Nat64 = U.get_neuron_nonce(vid, nodeMem.internals.local_idx);

                let neuron = NNS.Neuron({
                    nns_canister_id = icp_governance;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.spawn({ nonce = ?newNonce; new_controller = null; percentage_to_spawn = null })) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "spawn_maturity", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "spawn_maturity", #Err(debug_show err));
                    };
                };
            };
        };

        private func claim_maturity(nodeMem : N.Mem, destination : Node.DestinationEndpoint) : async* () {
            label spawnLoop for (spawningNeuron in nodeMem.internals.spawning_neurons.vals()) {
                // Once a neuron is spawned, the maturity is converted into staked ICP
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

                    switch (await* neuron.disburse({ to_account = ?{ hash = AI.accountIdentifier(account.owner, Option.get(account.subaccount, AI.defaultSubaccount())) |> Blob.toArray(_) }; amount = null })) {
                        case (#ok(_)) {
                            log_activity(nodeMem, "claim_maturity", #Ok);
                        };
                        case (#err(err)) {
                            log_activity(nodeMem, "claim_maturity", #Err(debug_show err));
                        };
                    };
                };
            };
        };

        private func ready(nodeMem : N.Mem) : Bool {
            switch (nodeMem.internals.updating) {
                case (#Init) {
                    nodeMem.internals.updating := #Calling(U.get_now_nanos());
                    return true;
                };
                case (#Calling(ts) or #Done(ts)) {
                    if (U.get_now_nanos() >= ts + TIMEOUT_NANOS) {
                        nodeMem.internals.updating := #Calling(U.get_now_nanos());
                        return true;
                    } else {
                        return false;
                    };
                };
            };
        };

        private func log_activity(nodeMem : N.Mem, operation : Text, result : { #Ok; #Err : Text }) : () {
            let activityLog = Buffer.fromArray<N.Activity>(nodeMem.internals.activity_log);

            switch (result) {
                case (#Ok(())) {
                    activityLog.add(#Ok({ operation = operation; timestamp = U.get_now_nanos() }));
                };
                case (#Err(msg)) {
                    activityLog.add(#Err({ operation = operation; msg = msg; timestamp = U.get_now_nanos() }));
                };
            };

            if (activityLog.size() > ACTIVITY_LOG_LIMIT) {
                ignore activityLog.remove(0); // remove 1 item from the beginning
            };

            nodeMem.internals.activity_log := Buffer.toArray(activityLog);
        };
    };
};
