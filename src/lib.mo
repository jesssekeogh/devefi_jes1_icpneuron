import U "mo:devefi/utils";
import MU "mo:mosup";
import Map "mo:map/Map";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Core "mo:devefi/core";
import DeVeFi "mo:devefi";
import Vector "mo:vector/Class";
import Ver1 "./memory/v1";
import I "./interface";
import GovT "mo:neuro/interfaces/nns_interface";
import AI "mo:account-identifier";
import { NNS } "mo:neuro";
import Tools "mo:neuro/tools";

module {
    let T = Core.VectorModule;

    public let Interface = I;

    public module Mem {
        public module Vector {
            public let V1 = Ver1;
        };
    };

    let M = Mem.Vector.V1;

    public let ID = "nns";

    public class Mod({
        xmem : MU.MemShell<M.Mem>;
        core : Core.Mod;
        dvf : DeVeFi.DeVeFi;
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        let NNS_CANISTER_ID = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        let ICP_LEDGER_CANISTER_ID = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

        // Caches are checked again after this time
        let TIMEOUT_NANOS : Nat64 = (10 * 60 * 1_000_000_000);

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

        public func meta() : T.Meta {
            {
                id = ID; // This has to be same as the variant in vec.custom
                name = "NNS";
                author = "jes1";
                description = "Stake NNS Neurons";
                supported_ledgers = [#ic(ICP_LEDGER_CANISTER_ID)];
                version = #alpha([0, 0, 1]);
                create_allowed = true;
                ledger_slots = [
                    "Neuron"
                ];
                billing = {
                    cost_per_day = 10_0000; // TODO change
                    transaction_fee = #none;
                };
                sources = sources(0);
                destinations = destinations(0);
                author_account = {
                    owner = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"); // TODO change
                    subaccount = null;
                };
            };
        };

        public func run(id : T.NodeId, vec : T.NodeCoreMem) : () {
            let ?nodeMem = Map.get(mem.main, Map.n32hash, id) else return;
            let ?source = core.getSource(id, vec, 0) else return;

            let bal = core.Source.balance(source);
            let fee = core.Source.fee(source);

            if (bal <= fee) return;

            let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(dvf.me(), get_neuron_nonce(id, 0));

            // TODO enforce a minimum

            let #ok(txId) = core.Source.send(source, #external_account({ owner = NNS_CANISTER_ID; subaccount = ?neuronSubaccount }), bal) else return;
            // if a neuron exists, we refresh
            if (Option.isSome(nodeMem.cache.neuron_id)) {
                let txs = Vector.fromArray<Nat64>(nodeMem.internals.refresh_idx);
                txs.add(txId);
                nodeMem.internals.refresh_idx := Vector.toArray(txs);
            };
        };

        public func runAsync(id : T.NodeId, vec : T.NodeCoreMem) : async* () {
            let ?nodeMem = Map.get(mem.main, Map.n32hash, id) else return;

            if (not ready(nodeMem)) return;
            try {
                await* refresh_cache(nodeMem, id);
                await* claim_neuron(nodeMem, id);
                await* refresh_neuron(nodeMem);
                await* update_delay(nodeMem);
                await* update_followees(nodeMem);
                await* update_dissolving(nodeMem);
                await* disburse_neuron(nodeMem, vec.refund);
                await* spawn_maturity(nodeMem, id);
                await* claim_maturity(nodeMem, vec.destinations[0]);
            } catch (err) {
                log_activity(nodeMem, "async_cycle", #Err(Error.message(err)));
            } finally {
                nodeMem.internals.updating := #Done(U.now());
            };
        };

        public func create(id : T.NodeId, t : I.CreateRequest) : T.Create {
            let obj : M.NodeMem = {
                variables = {
                    var update_delay_seconds = t.variables.update_delay_seconds;
                    var update_followee = t.variables.update_followee;
                    var update_dissolving = t.variables.update_dissolving;
                };
                internals = {
                    var updating = #Init;
                    var local_idx = 0;
                    var refresh_idx = [];
                    var spawning_neurons = [];
                    var activity_log = [];
                };
                cache = {
                    var neuron_id = null;
                    var nonce = null;
                    var maturity_e8s_equivalent = null;
                    var cached_neuron_stake_e8s = null;
                    var created_timestamp_seconds = null;
                    var followees = [];
                    var dissolve_delay_seconds = null;
                    var state = null;
                    var voting_power = null;
                    var age_seconds = null;
                };
            };
            ignore Map.put(mem.main, Map.n32hash, id, obj);
            #ok(ID);
        };

        public func delete(_id : T.NodeId) : () {
            // Not allowed:
            // ignore Map.remove(mem.main, Map.n32hash, id);
        };

        public func modify(id : T.NodeId, m : I.ModifyRequest) : T.Modify {
            let ?t = Map.get(mem.main, Map.n32hash, id) else return #err("Not found");

            t.variables.update_delay_seconds := Option.get(m.update_delay_seconds, t.variables.update_delay_seconds);
            t.variables.update_followee := Option.get(m.update_followee, t.variables.update_followee);
            t.variables.update_dissolving := Option.get(m.update_dissolving, t.variables.update_dissolving);
            #ok();
        };

        public func get(id : T.NodeId) : T.Get<I.Shared> {
            let ?t = Map.get(mem.main, Map.n32hash, id) else return #err("Not found");

            #ok {
                variables = {
                    update_delay_seconds = t.variables.update_delay_seconds;
                    update_followee = t.variables.update_followee;
                    update_dissolving = t.variables.update_dissolving;
                };
                internals = {
                    updating = t.internals.updating;
                    local_idx = t.internals.local_idx;
                    refresh_idx = t.internals.refresh_idx;
                    spawning_neurons = Array.map(
                        t.internals.spawning_neurons,
                        func(neuron : Ver1.SpawningNeuronCache) : I.SharedSpawningNeuronCache {

                            {
                                nonce = neuron.nonce;
                                maturity_e8s_equivalent = neuron.maturity_e8s_equivalent;
                                cached_neuron_stake_e8s = neuron.cached_neuron_stake_e8s;
                                created_timestamp_seconds = neuron.created_timestamp_seconds;
                            };
                        },
                    );
                    activity_log = t.internals.activity_log;
                };
                cache = {
                    neuron_id = t.cache.neuron_id;
                    nonce = t.cache.nonce;
                    maturity_e8s_equivalent = t.cache.maturity_e8s_equivalent;
                    cached_neuron_stake_e8s = t.cache.cached_neuron_stake_e8s;
                    created_timestamp_seconds = t.cache.created_timestamp_seconds;
                    followees = t.cache.followees;
                    dissolve_delay_seconds = t.cache.dissolve_delay_seconds;
                    state = t.cache.state;
                    voting_power = t.cache.voting_power;
                    age_seconds = t.cache.age_seconds;
                };
            };
        };

        public func defaults() : I.CreateRequest {
            {
                variables = {
                    update_delay_seconds = 15897600; // 184 days
                    update_followee = 8571487073262291504; // neuronpool known neuron
                    update_dissolving = false; // not dissolving
                };
            };
        };

        public func sources(_id : T.NodeId) : T.Endpoints {
            [(0, "Stake")];
        };

        public func destinations(_id : T.NodeId) : T.Endpoints {
            [(0, "Maturity")];
        };

        let nns = NNS.Governance({
            canister_id = dvf.me();
            nns_canister_id = NNS_CANISTER_ID;
            icp_ledger_canister_id = ICP_LEDGER_CANISTER_ID;
        });

        public func refresh_cache(nodeMem : Ver1.NodeMem, vid : Nat32) : async* () {
            // Use list_neurons to update caches and find empty neurons.
            // Fetch all neurons owned by the canister to locate the neuron owned by the node and all its spawning neurons.
            // Possible enhancements include using a separate cache cycle that updates all nodes in one call
            // and not fetching empty neurons. Tests show that fetching over 10,000 neurons is fine, but performance should be monitored.
            let { full_neurons; neuron_infos } = await* nns.listNeurons({
                neuron_ids = [];
                include_readable = true;
                include_public = true;
                include_empty = true;
            });

            let neuronInfos = Map.fromIter<Nat64, GovT.NeuronInfo>(neuron_infos.vals(), Map.n64hash);

            let fullNeurons = Map.fromIterMap<Blob, GovT.Neuron, GovT.Neuron>(
                full_neurons.vals(),
                Map.bhash,
                func(neuron : GovT.Neuron) : ?(Blob, GovT.Neuron) {
                    return ?(Blob.fromArray(neuron.account), neuron);
                },
            );

            update_neuron_cache(nodeMem, neuronInfos, fullNeurons);
            update_spawning_neurons_cache(nodeMem, vid, fullNeurons);
        };

        private func update_neuron_cache(nodeMem : Ver1.NodeMem, neuronInfos : Map.Map<Nat64, GovT.NeuronInfo>, fullNeurons : Map.Map<Blob, GovT.Neuron>) : () {
            let ?nid = nodeMem.cache.neuron_id else return;
            let ?nonce = nodeMem.cache.nonce else return;

            let neuronSub : Blob = Tools.computeNeuronStakingSubaccountBytes(dvf.me(), nonce);

            switch (Map.get(neuronInfos, Map.n64hash, nid), Map.get(fullNeurons, Map.bhash, neuronSub)) {
                case (?info, ?full) {
                    nodeMem.cache.maturity_e8s_equivalent := ?full.maturity_e8s_equivalent;
                    nodeMem.cache.cached_neuron_stake_e8s := ?full.cached_neuron_stake_e8s;
                    nodeMem.cache.created_timestamp_seconds := ?full.created_timestamp_seconds;
                    nodeMem.cache.followees := full.followees;
                    nodeMem.cache.dissolve_delay_seconds := ?info.dissolve_delay_seconds;
                    nodeMem.cache.state := ?info.state;
                    nodeMem.cache.voting_power := ?info.voting_power;
                    nodeMem.cache.age_seconds := ?info.age_seconds;
                };
                case (_) { return };
            };
        };

        private func update_spawning_neurons_cache(nodeMem : Ver1.NodeMem, vid : Nat32, fullNeurons : Map.Map<Blob, GovT.Neuron>) : () {
            let spawningNeurons = Vector.Vector<Ver1.SpawningNeuronCache>();

            // finds neurons that this vector owner has created and adds them to the cache
            // start at 1, 0 is reserved for the vectors main neuron
            var idx : Nat32 = 1;
            label idxLoop while (idx <= nodeMem.internals.local_idx) {
                let spawningNonce : Nat64 = get_neuron_nonce(vid, idx);
                let spawningSub : Blob = Tools.computeNeuronStakingSubaccountBytes(dvf.me(), spawningNonce);
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

        private func claim_neuron(nodeMem : Ver1.NodeMem, vid : Nat32) : async* () {
            if (Option.isSome(nodeMem.cache.neuron_id)) return;
            let firstNonce = get_neuron_nonce(vid, 0); // first localIdx for every neuron is always 0
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

        private func refresh_neuron(nodeMem : Ver1.NodeMem) : async* () {
            let ?{ cls = #icp(ledger) } = dvf.get_ledger(ICP_LEDGER_CANISTER_ID) else return;
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

        private func update_delay(nodeMem : Ver1.NodeMem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?cachedDelay = nodeMem.cache.dissolve_delay_seconds else return;
            let delayToSet = nodeMem.variables.update_delay_seconds;

            if (delayToSet > cachedDelay + DELAY_BUFFER_SECONDS and delayToSet <= MAXIMUM_DELAY_SECONDS) {
                let neuron = NNS.Neuron({
                    nns_canister_id = NNS_CANISTER_ID;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = (U.now() / 1_000_000_000) + delayToSet })) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "update_delay", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "update_delay", #Err(debug_show err));
                    };
                };
            };
        };

        private func update_followees(nodeMem : Ver1.NodeMem) : async* () {
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
                        nns_canister_id = NNS_CANISTER_ID;
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

        private func update_dissolving(nodeMem : Ver1.NodeMem) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?dissolvingState = nodeMem.cache.state else return;
            let updateDissolving = nodeMem.variables.update_dissolving;

            if (updateDissolving and dissolvingState == NEURON_STATES.locked) {
                let neuron = NNS.Neuron({
                    nns_canister_id = NNS_CANISTER_ID;
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
                    nns_canister_id = NNS_CANISTER_ID;
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

        private func disburse_neuron(nodeMem : Ver1.NodeMem, refund : Core.Account) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?dissolvingState = nodeMem.cache.state else return;
            let ?cachedStake = nodeMem.cache.cached_neuron_stake_e8s else return;
            let updateDissolving = nodeMem.variables.update_dissolving;

            if (updateDissolving and dissolvingState == NEURON_STATES.unlocked and cachedStake > 0) {
                let neuron = NNS.Neuron({
                    nns_canister_id = NNS_CANISTER_ID;
                    neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                });

                switch (await* neuron.disburse({ to_account = ?{ hash = AI.accountIdentifier(refund.owner, Option.get(refund.subaccount, AI.defaultSubaccount())) }; amount = null })) {
                    case (#ok(_)) {
                        log_activity(nodeMem, "disburse_neuron", #Ok);
                    };
                    case (#err(err)) {
                        log_activity(nodeMem, "disburse_neuron", #Err(debug_show err));
                    };
                };
            };
        };

        private func spawn_maturity(nodeMem : Ver1.NodeMem, vid : Nat32) : async* () {
            let ?neuron_id = nodeMem.cache.neuron_id else return;
            let ?cachedMaturity = nodeMem.cache.maturity_e8s_equivalent else return;

            if (cachedMaturity > MINIMUM_SPAWN) {
                nodeMem.internals.local_idx += 1;
                let newNonce : Nat64 = get_neuron_nonce(vid, nodeMem.internals.local_idx);

                let neuron = NNS.Neuron({
                    nns_canister_id = NNS_CANISTER_ID;
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

        private func claim_maturity(nodeMem : Ver1.NodeMem, destination : Core.EndpointOptStored) : async* () {
            label spawnLoop for (spawningNeuron in nodeMem.internals.spawning_neurons.vals()) {
                // Once a neuron is spawned, the maturity is converted into staked ICP
                if (spawningNeuron.cached_neuron_stake_e8s > 0) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #Subaccount(
                            Blob.toArray(
                                Tools.computeNeuronStakingSubaccountBytes(dvf.me(), spawningNeuron.nonce)
                            )
                        );
                    });

                    let { endpoint = #ic({ account = ?account }) } = destination else continue spawnLoop;

                    switch (await* neuron.disburse({ to_account = ?{ hash = AI.accountIdentifier(account.owner, Option.get(account.subaccount, AI.defaultSubaccount())) }; amount = null })) {
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

        private func ready(nodeMem : Ver1.NodeMem) : Bool {
            switch (nodeMem.internals.updating) {
                case (#Init) {
                    nodeMem.internals.updating := #Calling(U.now());
                    return true;
                };
                case (#Calling(ts) or #Done(ts)) {
                    if (U.now() >= ts + TIMEOUT_NANOS) {
                        nodeMem.internals.updating := #Calling(U.now());
                        return true;
                    } else {
                        return false;
                    };
                };
            };
        };

        private func log_activity(nodeMem : Ver1.NodeMem, operation : Text, result : { #Ok; #Err : Text }) : () {
            let activityLog = Buffer.fromArray<Ver1.Activity>(nodeMem.internals.activity_log);

            switch (result) {
                case (#Ok(())) {
                    activityLog.add(#Ok({ operation = operation; timestamp = U.now() }));
                };
                case (#Err(msg)) {
                    activityLog.add(#Err({ operation = operation; msg = msg; timestamp = U.now() }));
                };
            };

            if (activityLog.size() > ACTIVITY_LOG_LIMIT) {
                ignore activityLog.remove(0); // remove 1 item from the beginning
            };

            nodeMem.internals.activity_log := Buffer.toArray(activityLog);
        };

        private func get_neuron_nonce(vid : Nat32, localId : Nat32) : Nat64 {
            return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
        };

    };
};
