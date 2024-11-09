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
import Vector "mo:vector/Class";
import Ver1 "./memory/v1";
import I "./interface";
import GovT "mo:neuro/interfaces/nns_interface";
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
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        let NNS_CANISTER_ID = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        let ICP_LEDGER_CANISTER_ID = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

        // Interval for cache check when no neuron refresh is pending.
        // Maturity accumulates only once per day, allowing at most one neuron spawn daily.
        let TIMEOUT_NANOS_NO_REFRESH_PENDING : Nat64 = (12 * 60 * 60 * 1_000_000_000); // every 12 hours

        // Timeout interval for when a neuron refresh is pending.
        let TIMEOUT_NANOS_REFRESH_PENDING : Nat64 = (5 * 60 * 1_000_000_000); // every 5 minutes

        // 20.00 ICP in e8s
        let MINIMUM_STAKE : Nat = 2_000_000_000;

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
                    cost_per_day = 0;
                    transaction_fee = #flat_fee_multiplier(500); // TODO make a proper estimate
                };
                sources = sources(0);
                destinations = destinations(0);
                author_account = {
                    // owner = Principal.fromText(
                    //     "jv4ws-fbili-a35rv-xd7a5-xwvxw-trink-oluun-g7bcp-oq5f6-35cba-vqe"
                    // );
                    owner = Principal.fromText(
                        "ydl4r-asr5o-7axs3-tshas-4xugy-bvg4x-ixnjd-6qex3-guw6d-5pahc-oqe" // TODO remove, used for testing
                    );
                    subaccount = null;
                };
                temporary_allowed = true;
            };
        };

        public func run() : () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                Run.single(vid, vec, nodeMem);
            };
        };

        public func runAsync() : async* () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                await* Run.singleAsync(vid, vec, nodeMem);
            };
        };

        module Run {
            public func single(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : M.NodeMem) : () {
                let ?sourceStake = core.getSource(vid, vec, 0) else return;
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;

                // fee is the same
                let fee = core.Source.fee(sourceStake);

                let stakeBal = core.Source.balance(sourceStake);
                let maturityBal = core.Source.balance(sourceMaturity);
                let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), NodeUtils.get_neuron_nonce(vid, 0));

                // If a neuron exists, a smaller amoount is required for increasing the existing stake.
                // If no neuron exists, enforce the minimum stake requirement (plus fee) to create a new neuron.
                let requiredStake = if (Option.isSome(nodeMem.cache.neuron_id)) fee else MINIMUM_STAKE;

                if (stakeBal > requiredStake) {
                    // Proceed to send ICP to the neuron's subaccount
                    let #ok(txId) = core.Source.send(
                        sourceStake,
                        #external_account({
                            owner = NNS_CANISTER_ID;
                            subaccount = ?neuronSubaccount;
                        }),
                        stakeBal,
                    ) else return;

                    // Set refresh_idx to refresh or claim the neuron in the next round
                    NodeUtils.tx_sent(nodeMem, txId);
                };

                // forward all maturity
                if (maturityBal > fee) {
                    ignore core.Source.send(sourceMaturity, #destination({ port = 0 }), maturityBal);
                };
            };

            public func singleAsync(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : M.NodeMem) : async* () {
                try {
                    if (NodeUtils.node_ready(nodeMem)) {
                        await* NeuronActions.refresh_neuron(nodeMem, vid);
                        await* NeuronActions.update_delay(nodeMem);
                        await* NeuronActions.update_followees(nodeMem);
                        await* NeuronActions.update_dissolving(nodeMem);
                        await* NeuronActions.spawn_maturity(nodeMem, vid);
                        await* NeuronActions.claim_maturity(nodeMem, vec);
                        await* NeuronActions.disburse_neuron(nodeMem, vec.refund);
                        await* CacheManager.refresh_cache(nodeMem, vid);
                    };
                } catch (err) {
                    NodeUtils.log_activity(nodeMem, "async_cycle", #Err(Error.message(err)));
                } finally {
                    // `finally` is necessary as internal traps aren't caught by `catch`
                    // It always runs to update `nodeMem.internals.updating`
                    NodeUtils.node_done(nodeMem);
                };
            };
        };

        public func create(id : T.NodeId, _req : T.CommonCreateRequest, t : I.CreateRequest) : T.Create {
            let obj : M.NodeMem = {
                variables = {
                    var update_delay_seconds = t.variables.update_delay_seconds;
                    var update_followee = t.variables.update_followee;
                    var update_dissolving = t.variables.update_dissolving;
                };
                internals = {
                    var updating = #Init;
                    var local_idx = 0;
                    var refresh_idx = null;
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

        public func delete(id : T.NodeId) : T.Delete {
            let ?t = Map.get(mem.main, Map.n32hash, id) else return #err("Not found");

            let cachedStake = Option.get(t.cache.cached_neuron_stake_e8s, 0);
            if (cachedStake == 0) {
                ignore Map.remove(mem.main, Map.n32hash, id);
                return #ok();
            };

            return #err("Neuron is not empty");
        };

        public func modify(id : T.NodeId, m : I.ModifyRequest) : T.Modify {
            let ?t = Map.get(mem.main, Map.n32hash, id) else return #err("Not found");

            t.variables.update_delay_seconds := Option.get(m.update_delay_seconds, t.variables.update_delay_seconds);
            t.variables.update_followee := Option.get(m.update_followee, t.variables.update_followee);
            t.variables.update_dissolving := Option.get(m.update_dissolving, t.variables.update_dissolving);
            #ok();
        };

        public func get(id : T.NodeId, _vec : T.NodeCoreMem) : T.Get<I.Shared> {
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
                        func(neuron : Ver1.NeuronCache) : I.SharedNeuronCache {
                            {
                                neuron_id = neuron.neuron_id;
                                nonce = neuron.nonce;
                                maturity_e8s_equivalent = neuron.maturity_e8s_equivalent;
                                cached_neuron_stake_e8s = neuron.cached_neuron_stake_e8s;
                                created_timestamp_seconds = neuron.created_timestamp_seconds;
                                followees = neuron.followees;
                                dissolve_delay_seconds = neuron.dissolve_delay_seconds;
                                state = neuron.state;
                                voting_power = neuron.voting_power;
                                age_seconds = neuron.age_seconds;
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
                    update_dissolving = #KeepLocked;
                };
            };
        };

        public func sources(_id : T.NodeId) : T.Endpoints {
            [(0, "Stake"), (0, "_Maturity")];
        };

        public func destinations(_id : T.NodeId) : T.Endpoints {
            [(0, "Maturity")];
        };

        let nns = NNS.Governance({
            canister_id = core.getThisCan();
            nns_canister_id = NNS_CANISTER_ID;
            icp_ledger_canister_id = ICP_LEDGER_CANISTER_ID;
        });

        module NodeUtils {
            public func node_ready(nodeMem : Ver1.NodeMem) : Bool {
                // Determine the appropriate timeout based on whether the neuron should be refreshed
                let timeout = if (node_needs_refresh(nodeMem)) {
                    TIMEOUT_NANOS_REFRESH_PENDING;
                } else {
                    TIMEOUT_NANOS_NO_REFRESH_PENDING;
                };

                switch (nodeMem.internals.updating) {
                    case (#Init) {
                        nodeMem.internals.updating := #Calling(U.now());
                        return true;
                    };
                    case (#Calling(ts) or #Done(ts)) {
                        if (U.now() >= ts + timeout) {
                            nodeMem.internals.updating := #Calling(U.now());
                            return true;
                        } else {
                            return false;
                        };
                    };
                };
            };

            private func node_needs_refresh(nodeMem : Ver1.NodeMem) : Bool {
                return (
                    Option.isSome(nodeMem.internals.refresh_idx) or
                    CacheManager.followee_changed(nodeMem, GOVERNANCE_TOPICS[0]) or
                    CacheManager.dissolving_changed(nodeMem) or
                    CacheManager.delay_changed(nodeMem)
                );
            };

            public func node_done(nodeMem : Ver1.NodeMem) : () {
                nodeMem.internals.updating := #Done(U.now());
            };

            public func tx_sent(nodeMem : Ver1.NodeMem, txId : Nat64) : () {
                nodeMem.internals.refresh_idx := ?txId;
            };

            public func log_activity(nodeMem : Ver1.NodeMem, operation : Text, result : { #Ok; #Err : Text }) : () {
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

            public func get_neuron_nonce(vid : T.NodeId, localId : Nat32) : Nat64 {
                return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
            };
        };

        module CacheManager {
            public func refresh_cache(nodeMem : Ver1.NodeMem, vid : T.NodeId) : async* () {
                let ?nid = nodeMem.cache.neuron_id else return;

                let { full_neurons; neuron_infos } = await* nns.listNeurons({
                    neuron_ids = [nid]; // always fetch the main neuron
                    include_readable = true;
                    include_public = true;
                    include_empty = true; // TODO set to false in production
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
                update_spawning_neurons_cache(nodeMem, vid, neuronInfos, fullNeurons);
            };

            private func update_neuron_cache(
                nodeMem : Ver1.NodeMem,
                neuronInfos : Map.Map<Nat64, GovT.NeuronInfo>,
                fullNeurons : Map.Map<Blob, GovT.Neuron>,
            ) : () {
                let ?nid = nodeMem.cache.neuron_id else return;
                let ?nonce = nodeMem.cache.nonce else return;

                let neuronSub : Blob = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), nonce);

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

            private func update_spawning_neurons_cache(
                nodeMem : Ver1.NodeMem,
                vid : Nat32,
                neuronInfos : Map.Map<Nat64, GovT.NeuronInfo>,
                fullNeurons : Map.Map<Blob, GovT.Neuron>,
            ) : () {
                let spawningNeurons = Vector.Vector<Ver1.NeuronCache>();

                // finds neurons that this vector owner has created and adds them to the cache
                // start at 1, 0 is reserved for the vectors main neuron
                var idx : Nat32 = 1;
                label idxLoop while (idx <= nodeMem.internals.local_idx) {
                    let spawningNonce : Nat64 = NodeUtils.get_neuron_nonce(vid, idx);
                    let spawningSub : Blob = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), spawningNonce);

                    let ?full = Map.get(fullNeurons, Map.bhash, spawningSub) else continue idxLoop;
                    let ?nid = full.id else continue idxLoop;
                    let ?info = Map.get(neuronInfos, Map.n64hash, nid.id) else continue idxLoop;

                    // adds spawning neurons too, a possible memory adjustment could be to just add spawned neurons,
                    // it is nice to show the vector owner the neurons that are spawning though
                    if (full.cached_neuron_stake_e8s > 0 or full.maturity_e8s_equivalent > 0) {
                        spawningNeurons.add({
                            var neuron_id = ?nid.id;
                            var nonce = ?spawningNonce;
                            var maturity_e8s_equivalent = ?full.maturity_e8s_equivalent;
                            var cached_neuron_stake_e8s = ?full.cached_neuron_stake_e8s;
                            var created_timestamp_seconds = ?full.created_timestamp_seconds;
                            var followees = full.followees;
                            var dissolve_delay_seconds = ?info.dissolve_delay_seconds;
                            var state = ?info.state;
                            var voting_power = ?info.voting_power;
                            var age_seconds = ?info.age_seconds;
                        });
                    };
                    idx += 1;
                };

                nodeMem.internals.spawning_neurons := Vector.toArray(spawningNeurons);
            };

            public func delay_changed(nodeMem : Ver1.NodeMem) : Bool {
                let ?cachedDelay = nodeMem.cache.dissolve_delay_seconds else return true;
                let delayToSet = nodeMem.variables.update_delay_seconds;
                return delayToSet > cachedDelay + DELAY_BUFFER_SECONDS and delayToSet <= MAXIMUM_DELAY_SECONDS;
            };

            public func followee_changed(nodeMem : Ver1.NodeMem, topic : Int32) : Bool {
                let currentFollowees = Map.fromIter<Int32, GovT.Followees>(nodeMem.cache.followees.vals(), Map.i32hash);
                let followeeToSet = nodeMem.variables.update_followee;

                switch (Map.get(currentFollowees, Map.i32hash, topic)) {
                    case (?{ followees }) {
                        return followees[0].id != followeeToSet;
                    };
                    case _ { return true };
                };
            };

            public func dissolving_changed(nodeMem : Ver1.NodeMem) : Bool {
                let ?dissolvingState = nodeMem.cache.state else return false;

                switch (nodeMem.variables.update_dissolving) {
                    case (#StartDissolving) {
                        return dissolvingState == NEURON_STATES.locked;
                    };
                    case (#KeepLocked) {
                        return dissolvingState == NEURON_STATES.dissolving;
                    };
                };
            };
        };

        module NeuronActions {
            public func refresh_neuron(nodeMem : Ver1.NodeMem, vid : T.NodeId) : async* () {
                let firstNonce = NodeUtils.get_neuron_nonce(vid, 0); // first localIdx for every neuron is always 0
                let ?{ cls = #icp(ledger) } = core.get_ledger_cls(ICP_LEDGER_CANISTER_ID) else return;
                let ?refreshIdx = nodeMem.internals.refresh_idx else return;

                if (ledger.isSent(refreshIdx)) {
                    switch (await* nns.claimNeuron({ nonce = firstNonce })) {
                        case (#ok(neuronId)) {
                            // if no neuron, set these values once
                            if (not Option.isSome(nodeMem.cache.neuron_id)) {
                                // Store the neuron's ID and nonce in the cache
                                nodeMem.cache.neuron_id := ?neuronId;
                                nodeMem.cache.nonce := ?firstNonce;
                            };

                            // Check if refreshIdx hasn't changed during the async call.
                            // If it hasn't changed, it's safe to reset refresh_idx to null.
                            if (Option.equal(?refreshIdx, nodeMem.internals.refresh_idx, Nat64.equal)) {
                                nodeMem.internals.refresh_idx := null;
                            };

                            NodeUtils.log_activity(nodeMem, "refresh_neuron", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "refresh_neuron", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_delay(nodeMem : Ver1.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                if (CacheManager.delay_changed(nodeMem)) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    let nowSecs = U.now() / 1_000_000_000;

                    switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = nowSecs + nodeMem.variables.update_delay_seconds })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_followees(nodeMem : Ver1.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                for (topic in GOVERNANCE_TOPICS.vals()) {
                    if (CacheManager.followee_changed(nodeMem, topic)) {
                        let neuron = NNS.Neuron({
                            nns_canister_id = NNS_CANISTER_ID;
                            neuron_id_or_subaccount = #NeuronId({
                                id = neuron_id;
                            });
                        });

                        switch (await* neuron.follow({ topic = topic; followee = nodeMem.variables.update_followee })) {
                            case (#ok(_)) {
                                NodeUtils.log_activity(nodeMem, "update_followees", #Ok);
                            };
                            case (#err(err)) {
                                NodeUtils.log_activity(nodeMem, "update_followees", #Err(debug_show err));
                            };
                        };
                    };
                };
            };

            public func update_dissolving(nodeMem : Ver1.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                if (CacheManager.dissolving_changed(nodeMem)) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    switch (nodeMem.variables.update_dissolving) {
                        case (#StartDissolving) {
                            switch (await* neuron.startDissolving()) {
                                case (#ok(_)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Ok);
                                };
                                case (#err(err)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Err(debug_show err));
                                };
                            };
                        };
                        case (#KeepLocked) {
                            switch (await* neuron.stopDissolving()) {
                                case (#ok(_)) {
                                    NodeUtils.log_activity(nodeMem, "stop_dissolving", #Ok);
                                };
                                case (#err(err)) {
                                    NodeUtils.log_activity(nodeMem, "stop_dissolving", #Err(debug_show err));
                                };
                            };
                        };
                    };
                };
            };

            public func spawn_maturity(nodeMem : Ver1.NodeMem, vid : T.NodeId) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;
                let ?cachedMaturity = nodeMem.cache.maturity_e8s_equivalent else return;

                if (cachedMaturity > MINIMUM_SPAWN) {
                    nodeMem.internals.local_idx += 1;
                    let newNonce : Nat64 = NodeUtils.get_neuron_nonce(vid, nodeMem.internals.local_idx);

                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    switch (await* neuron.spawn({ nonce = ?newNonce; new_controller = null; percentage_to_spawn = null })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "spawn_maturity", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "spawn_maturity", #Err(debug_show err));
                        };
                    };
                };
            };

            public func claim_maturity(nodeMem : Ver1.NodeMem, vec : T.NodeCoreMem) : async* () {
                label spawnLoop for (spawningNeuron in nodeMem.internals.spawning_neurons.vals()) {
                    let ?cachedStake = spawningNeuron.cached_neuron_stake_e8s else continue spawnLoop;

                    // Once a neuron is spawned, the maturity is converted into staked ICP
                    if (cachedStake > 0) {
                        let ?nonce = spawningNeuron.nonce else continue spawnLoop;

                        let neuron = NNS.Neuron({
                            nns_canister_id = NNS_CANISTER_ID;
                            neuron_id_or_subaccount = #Subaccount(
                                Blob.toArray(
                                    Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), nonce)
                                )
                            );
                        });

                        let ?account = core.getSourceAccountIC(vec, 1) else return;

                        switch (await* neuron.disburse({ to_account = ?{ hash = Principal.toLedgerAccount(account.owner, account.subaccount) }; amount = null })) {
                            case (#ok(_)) {
                                NodeUtils.log_activity(nodeMem, "claim_maturity", #Ok);
                            };
                            case (#err(err)) {
                                NodeUtils.log_activity(nodeMem, "claim_maturity", #Err(debug_show err));
                            };
                        };
                    };
                };
            };

            public func disburse_neuron(nodeMem : Ver1.NodeMem, refund : Core.Account) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;
                let ?dissolvingState = nodeMem.cache.state else return;
                let ?cachedStake = nodeMem.cache.cached_neuron_stake_e8s else return;

                let userWantsToDisburse = switch (nodeMem.variables.update_dissolving) {
                    case (#StartDissolving) { true };
                    case (#KeepLocked) { false };
                };

                if (userWantsToDisburse and dissolvingState == NEURON_STATES.unlocked and cachedStake > 0) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    switch (await* neuron.disburse({ to_account = ?{ hash = Principal.toLedgerAccount(refund.owner, refund.subaccount) }; amount = null })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Err(debug_show err));
                        };
                    };
                };
            };
        };
    };
};
