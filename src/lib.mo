import U "mo:devefi/utils";
import MU "mo:mosup";
import Map "mo:map/Map";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Core "mo:devefi/core";
import Ver1 "./memory/v1";
import Ver2 "./memory/v2";
import I "./interface";
import { NNS } "mo:neuro";
import Tools "mo:neuro/tools";

module {
    let T = Core.VectorModule;

    public let Interface = I;

    public module Mem {
        public module Vector {
            public let V1 = Ver1;
            public let V2 = Ver2;
        };
    };

    let M = Mem.Vector.V2;

    public let ID = "devefi_jes1_icpneuron";

    public class Mod({
        xmem : MU.MemShell<M.Mem>;
        core : Core.Mod;
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        let NNS_CANISTER_ID = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        let ICP_LEDGER_CANISTER_ID = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

        // Number of recent subaccounts to query (leaves plenty of room to catch up)
        let MAX_SUBACCOUNTS_TO_QUERY : Nat32 = 30;

        // Interval for cache check when no neuron refresh is pending.
        // Maturity accumulates only once per day, allowing at most one neuron spawn daily.
        let TIMEOUT_NANOS_NO_REFRESH_PENDING : Nat64 = (12 * 60 * 60 * 1_000_000_000); // every 12 hours

        // Timeout interval for when a neuron refresh is pending.
        let TIMEOUT_NANOS_REFRESH_PENDING : Nat64 = (3 * 60 * 1_000_000_000); // every 3 minutes

        let DEFAULT_NEURON_FOLLOWEE : Nat64 = 6914974521667616512; // Rakeoff.io named neuron

        // 20.00 ICP in e8s
        let MINIMUM_STAKE : Nat = 2_000_000_000;

        // 1.06 ICP in e8s
        let MINIMUM_SPAWN : Nat64 = 106_000_000;

        // Maximum number of activities to keep in the main neuron's activity log
        let ACTIVITY_LOG_LIMIT : Nat = 10;

        // Used to calculate days as seconds for delay inputs
        let ONE_DAY_SECONDS : Nat64 = 24 * 60 * 60;

        // Minimum dissolve delay to vote and earn rewards
        let MINIMUM_DELAY_SECONDS : Nat64 = (184 * ONE_DAY_SECONDS);

        // Minimum allowable delay increase, defined as a buffer of two weeks (in seconds)
        let DELAY_BUFFER_SECONDS : Nat64 = (14 * ONE_DAY_SECONDS);

        // From here: https://github.com/dfinity/ic/blob/master/rs/nervous_system/common/src/lib.rs#L67C15-L67C27
        let ONE_YEAR_SECONDS : Nat64 = (4 * 365 + 1) * ONE_DAY_SECONDS / 4;

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/src/governance.rs#L164
        let MAXIMUM_DELAY_SECONDS : Nat64 = 8 * ONE_YEAR_SECONDS;

        // Timeout interval for when a neurons voting power needs to be refreshed
        let TIMEOUT_REFRESH_VOTING_POWER_SECONDS : Nat64 = 90 * ONE_DAY_SECONDS; // every 90 days

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
                name = "ICP Neuron";
                author = "jes1";
                description = "Stake ICP neurons and receive maturity directly to your destination";
                supported_ledgers = [#ic(ICP_LEDGER_CANISTER_ID)];
                version = #beta([0, 2, 2]);
                create_allowed = true;
                ledger_slots = [
                    "Neuron"
                ];
                billing = [
                    {
                        cost_per_day = 0;
                        transaction_fee = #transaction_percentage_fee_e8s(5_000_000); // 5% fee
                    },
                    {
                        cost_per_day = 3_1700_0000; // 3.17 tokens
                        transaction_fee = #none;
                    },
                ];
                sources = sources(0);
                destinations = destinations(0);
                author_account = {
                    owner = Principal.fromText("jv4ws-fbili-a35rv-xd7a5-xwvxw-trink-oluun-g7bcp-oq5f6-35cba-vqe");
                    subaccount = null;
                };
                temporary_allowed = true;
            };
        };

        public func run() : () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                if (vec.billing.frozen) continue vec_loop; // don't run if frozen
                if (Option.isSome(vec.billing.expires)) continue vec_loop; // don't allow staking until fee paid
                Run.single(vid, vec, nodeMem);
            };
        };

        public func runAsync() : async* () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                if (vec.billing.frozen) continue vec_loop;
                if (Option.isSome(vec.billing.expires)) continue vec_loop;
                if (NodeUtils.node_ready(nodeMem)) {
                    await* Run.singleAsync(vid, vec, nodeMem);
                    return; // return after finding the first ready node
                };
            };
        };

        module Run {
            public func single(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : M.NodeMem) : () {
                let ?sourceStake = core.getSource(vid, vec, 0) else return;
                let stakeBal = core.Source.balance(sourceStake);
                let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), NodeUtils.get_neuron_nonce(vid, 0));

                // If a neuron exists, a smaller amount is required for increasing the existing stake.
                // If no neuron exists, enforce the minimum stake requirement (plus fee) to create a new neuron.
                let requiredStake = if (Option.isSome(nodeMem.cache.neuron_id)) core.Source.fee(sourceStake) else MINIMUM_STAKE;

                if (stakeBal > requiredStake) {
                    // Proceed to send ICP to the neuron's subaccount
                    let #ok(intent) = core.Source.Send.intent(
                        sourceStake,
                        #external_account({
                            owner = NNS_CANISTER_ID;
                            subaccount = ?neuronSubaccount;
                        }),
                        stakeBal,
                    ) else return;

                    let txId = core.Source.Send.commit(intent);

                    // Set refresh_idx to refresh or claim the neuron in the next round
                    NodeUtils.tx_sent(nodeMem, txId);
                };

                // forward all maturity
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;
                let maturityBal = core.Source.balance(sourceMaturity);

                // if cost per day billing option chosen, send maturity with no tx fee
                let maturityDestination = switch (vec.billing.billing_option) {
                    case (1) {
                        let ?account = core.getDestinationAccountIC(vec, 0) else return;
                        #external_account({
                            owner = account.owner;
                            subaccount = account.subaccount;
                        });
                    };
                    case (_) { #destination({ port = 0 }) };
                };

                let #ok(intent) = core.Source.Send.intent(
                    sourceMaturity,
                    maturityDestination,
                    maturityBal,
                ) else return;

                ignore core.Source.Send.commit(intent);
            };

            public func singleAsync(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : M.NodeMem) : async* () {
                try {
                    await* NeuronActions.refresh_neuron(nodeMem, vid);
                    await* NeuronActions.update_delay(nodeMem);
                    await* NeuronActions.update_followees(nodeMem);
                    await* NeuronActions.update_dissolving(nodeMem);
                    await* NeuronActions.spawn_maturity(nodeMem, vid);
                    await* NeuronActions.claim_maturity(nodeMem, vec);
                    await* NeuronActions.disburse_neuron(nodeMem, vec);
                    await* NeuronActions.refresh_voting_power(nodeMem);
                    await* CacheManager.refresh_cache(nodeMem, vid);
                } catch (err) {
                    NodeUtils.log_activity(nodeMem, "async_cycle", #Err(Error.message(err)));
                } finally {
                    NodeUtils.node_done(nodeMem);
                };
            };
        };

        public func create(vid : T.NodeId, _req : T.CommonCreateRequest, t : I.CreateRequest) : T.Create {
            let nodeMem : M.NodeMem = {
                variables = {
                    var dissolve_delay = t.variables.dissolve_delay;
                    var dissolve_status = t.variables.dissolve_status;
                    var followee = t.variables.followee;
                };
                internals = {
                    var updating = #Init;
                    var local_idx = 0;
                    var refresh_idx = null;
                    var spawning_neurons = [];
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
                    var voting_power_refreshed_timestamp_seconds = null;
                    var potential_voting_power = null;
                    var deciding_voting_power = null;
                };
                var log = [];
            };
            ignore Map.put(mem.main, Map.n32hash, vid, nodeMem);
            #ok(ID);
        };

        public func delete(vid : T.NodeId) : T.Delete {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            let shouldDelete = switch (t.cache.cached_neuron_stake_e8s) {
                case (?cachedStake) { if (cachedStake > 0) false else true };
                case (null) { true };
            };

            if (shouldDelete) {
                ignore Map.remove(mem.main, Map.n32hash, vid);
                return #ok();
            };

            return #err("Neuron is not empty");
        };

        public func modify(vid : T.NodeId, m : I.ModifyRequest) : T.Modify {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            t.variables.dissolve_delay := Option.get(m.dissolve_delay, t.variables.dissolve_delay);
            t.variables.dissolve_status := Option.get(m.dissolve_status, t.variables.dissolve_status);
            t.variables.followee := Option.get(m.followee, t.variables.followee);
            #ok();
        };

        public func get(vid : T.NodeId, _vec : T.NodeCoreMem) : T.Get<I.Shared> {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            #ok {
                variables = {
                    dissolve_delay = t.variables.dissolve_delay;
                    dissolve_status = t.variables.dissolve_status;
                    followee = t.variables.followee;
                };
                internals = {
                    updating = t.internals.updating;
                    local_idx = t.internals.local_idx;
                    refresh_idx = t.internals.refresh_idx;
                    spawning_neurons = Array.map(
                        t.internals.spawning_neurons,
                        func(neuron : Ver2.NeuronCache) : I.SharedNeuronCache {
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
                                voting_power_refreshed_timestamp_seconds = neuron.voting_power_refreshed_timestamp_seconds;
                                potential_voting_power = neuron.potential_voting_power;
                                deciding_voting_power = neuron.deciding_voting_power;
                            };
                        },
                    );
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
                    voting_power_refreshed_timestamp_seconds = t.cache.voting_power_refreshed_timestamp_seconds;
                    potential_voting_power = t.cache.potential_voting_power;
                    deciding_voting_power = t.cache.deciding_voting_power;
                };
                log = t.log;
            };
        };

        public func defaults() : I.CreateRequest {
            {
                variables = {
                    dissolve_delay = #Default;
                    dissolve_status = #Locked;
                    followee = #Default;
                };
            };
        };

        public func sources(_id : T.NodeId) : T.Endpoints {
            [(0, "Stake"), (0, "_Maturity")];
        };

        public func destinations(_id : T.NodeId) : T.Endpoints {
            [(0, "Maturity"), (0, "Disburse")];
        };

        let nns = NNS.Governance({
            canister_id = core.getThisCan();
            nns_canister_id = NNS_CANISTER_ID;
            icp_ledger_canister_id = ICP_LEDGER_CANISTER_ID;
        });

        module NodeUtils {
            public func node_ready(nodeMem : Ver2.NodeMem) : Bool {
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

            private func node_needs_refresh(nodeMem : Ver2.NodeMem) : Bool {
                return (
                    Option.isSome(nodeMem.internals.refresh_idx) or
                    CacheManager.followee_changed(nodeMem, GOVERNANCE_TOPICS[0]) or
                    CacheManager.dissolving_changed(nodeMem) or
                    CacheManager.delay_changed(nodeMem)
                );
            };

            public func node_done(nodeMem : Ver2.NodeMem) : () {
                nodeMem.internals.updating := #Done(U.now());
            };

            public func tx_sent(nodeMem : Ver2.NodeMem, txId : Nat64) : () {
                nodeMem.internals.refresh_idx := ?txId;
            };

            public func log_activity(nodeMem : Ver2.NodeMem, operation : Text, result : { #Ok; #Err : Text }) : () {
                let log = Buffer.fromArray<Ver2.Activity>(nodeMem.log);

                switch (result) {
                    case (#Ok(())) {
                        log.add(#Ok({ operation = operation; timestamp = U.now() }));
                    };
                    case (#Err(msg)) {
                        log.add(#Err({ operation = operation; msg = msg; timestamp = U.now() }));
                    };
                };

                if (log.size() > ACTIVITY_LOG_LIMIT) {
                    ignore log.remove(0); // remove 1 item from the beginning
                };

                nodeMem.log := Buffer.toArray(log);
            };

            public func get_neuron_nonce(vid : T.NodeId, localId : Nat32) : Nat64 {
                return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
            };
        };

        module CacheManager {
            private func compute_recent_subaccounts(vid : T.NodeId, localIdx : Nat32) : [{
                subaccount : Blob;
            }] {
                let buffer = Buffer.Buffer<{ subaccount : Blob }>(Nat32.toNat(MAX_SUBACCOUNTS_TO_QUERY));

                // Always include the main neuron's subaccount (index 0)
                let mainNonce = NodeUtils.get_neuron_nonce(vid, 0);
                let mainSubaccount = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), mainNonce);
                buffer.add({ subaccount = mainSubaccount });

                // Compute how many recent indices to check based on localIdx
                let startIdx : Nat32 = if (localIdx >= (MAX_SUBACCOUNTS_TO_QUERY) - 1) {
                    localIdx - ((MAX_SUBACCOUNTS_TO_QUERY) - 1);
                } else {
                    1;
                };

                // Add the most recent subaccounts (up to MAX_SUBACCOUNTS_TO_QUERY)
                label idxLoop for (idx in Iter.range(Nat32.toNat(startIdx), Nat32.toNat(localIdx))) {
                    let nonce = NodeUtils.get_neuron_nonce(vid, Nat32.fromNat(idx));
                    let subaccount = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), nonce);
                    buffer.add({ subaccount = subaccount });
                };

                return Buffer.toArray(buffer);
            };

            public func refresh_cache(nodeMem : Ver2.NodeMem, vid : T.NodeId) : async* () {
                if (Option.isNull(nodeMem.cache.neuron_id)) return;

                // Compute the subaccounts to query
                let subaccounts = compute_recent_subaccounts(vid, nodeMem.internals.local_idx);

                // Retrieve neurons owned by this canister using computed subaccounts
                let { full_neurons; neuron_infos } = await* nns.listNeurons({
                    include_empty = false;
                    include_public = false;
                    include_readable = false;
                    neuron_ids = [];
                    neuron_subaccounts = ?subaccounts;
                    page_number = null;
                    page_size = null;
                });

                // Convert results to maps for efficient lookups
                let neuronInfos = Map.fromIter<Nat64, I.NeuronInfo>(neuron_infos.vals(), Map.n64hash);
                let fullNeurons = Map.fromIterMap<Blob, I.Neuron, I.Neuron>(
                    full_neurons.vals(),
                    Map.bhash,
                    func(neuron : I.Neuron) : ?(Blob, I.Neuron) {
                        return ?(Blob.fromArray(neuron.account), neuron);
                    },
                );

                update_neuron_cache(nodeMem, neuronInfos, fullNeurons);
                update_spawning_neurons_cache(nodeMem, vid, neuronInfos, fullNeurons);
            };

            private func update_neuron_cache(
                nodeMem : Ver2.NodeMem,
                neuronInfos : Map.Map<Nat64, I.NeuronInfo>,
                fullNeurons : Map.Map<Blob, I.Neuron>,
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
                        nodeMem.cache.voting_power_refreshed_timestamp_seconds := full.voting_power_refreshed_timestamp_seconds;
                        nodeMem.cache.potential_voting_power := full.potential_voting_power;
                        nodeMem.cache.deciding_voting_power := full.deciding_voting_power;
                    };
                    case (_) { return };
                };
            };

            private func update_spawning_neurons_cache(
                nodeMem : Ver2.NodeMem,
                vid : Nat32,
                neuronInfos : Map.Map<Nat64, I.NeuronInfo>,
                fullNeurons : Map.Map<Blob, I.Neuron>,
            ) : () {
                let spawningNeurons = Buffer.Buffer<Ver2.NeuronCache>(8); // max of 7 spawning + 1 ready

                // Use the same logic as in compute_recent_subaccounts
                let startIdx : Nat32 = if (nodeMem.internals.local_idx >= (MAX_SUBACCOUNTS_TO_QUERY : Nat32) - 1) {
                    nodeMem.internals.local_idx - ((MAX_SUBACCOUNTS_TO_QUERY : Nat32) - 1);
                } else {
                    1;
                };

                // Only iterate through the recently queried spawning neurons
                label idxLoop for (idx in Iter.range(Nat32.toNat(startIdx), Nat32.toNat(nodeMem.internals.local_idx))) {
                    let spawningNonce : Nat64 = NodeUtils.get_neuron_nonce(vid, Nat32.fromNat(idx));
                    let spawningSub : Blob = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), spawningNonce);

                    let ?full = Map.get(fullNeurons, Map.bhash, spawningSub) else continue idxLoop;
                    let ?nid = full.id else continue idxLoop;
                    let ?info = Map.get(neuronInfos, Map.n64hash, nid.id) else continue idxLoop;

                    // only add the neuron if the maturity or stake is greater than 0
                    if (full.maturity_e8s_equivalent > 0 or full.cached_neuron_stake_e8s > 0) {
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
                            var voting_power_refreshed_timestamp_seconds = full.voting_power_refreshed_timestamp_seconds;
                            var potential_voting_power = full.potential_voting_power;
                            var deciding_voting_power = full.deciding_voting_power;
                        });
                    };
                };

                nodeMem.internals.spawning_neurons := Buffer.toArray(spawningNeurons);
            };

            public func delay_changed(nodeMem : Ver2.NodeMem) : Bool {
                if (Option.isNull(nodeMem.cache.neuron_id)) return false;
                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return false; // don't update delay if dissolving
                    };
                    case (#Locked) {
                        let ?cachedDelay = nodeMem.cache.dissolve_delay_seconds else return true;
                        let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                            case (#Default) { MINIMUM_DELAY_SECONDS };
                            case (#DelayDays(days)) { days * ONE_DAY_SECONDS };
                        };

                        return delayToSet > cachedDelay + DELAY_BUFFER_SECONDS;
                    };
                };
            };

            public func followee_changed(nodeMem : Ver2.NodeMem, topic : Int32) : Bool {
                if (Option.isNull(nodeMem.cache.neuron_id)) return false;
                let currentFollowees = Map.fromIter<Int32, { followees : [{ id : Nat64 }] }>(nodeMem.cache.followees.vals(), Map.i32hash);
                let followeeToSet : Nat64 = switch (nodeMem.variables.followee) {
                    case (#Default) { DEFAULT_NEURON_FOLLOWEE };
                    case (#FolloweeId(followee)) { followee };
                };

                switch (Map.get(currentFollowees, Map.i32hash, topic)) {
                    case (?{ followees }) {
                        return followees[0].id != followeeToSet;
                    };
                    case _ { return true };
                };
            };

            public func dissolving_changed(nodeMem : Ver2.NodeMem) : Bool {
                if (Option.isNull(nodeMem.cache.neuron_id)) return false;
                let ?dissolvingState = nodeMem.cache.state else return false;

                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return dissolvingState == NEURON_STATES.locked;
                    };
                    case (#Locked) {
                        return dissolvingState == NEURON_STATES.dissolving;
                    };
                };
            };
        };

        module NeuronActions {
            public func refresh_neuron(nodeMem : Ver2.NodeMem, vid : T.NodeId) : async* () {
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

            public func update_delay(nodeMem : Ver2.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                if (CacheManager.delay_changed(nodeMem)) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    let nowSecs = U.now() / 1_000_000_000;

                    let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                        case (#Default) { MINIMUM_DELAY_SECONDS };
                        case (#DelayDays(days)) { days * ONE_DAY_SECONDS };
                    };

                    let cleanedDelay = Nat64.min(
                        Nat64.max(delayToSet, MINIMUM_DELAY_SECONDS),
                        MAXIMUM_DELAY_SECONDS,
                    );

                    // Store the original delay in nodeMem, keeping it at the max if applicable
                    nodeMem.variables.dissolve_delay := #DelayDays(cleanedDelay / ONE_DAY_SECONDS);

                    // give the maximum a buffer so we can reach 8 years
                    let adjustedDelay = if (cleanedDelay == MAXIMUM_DELAY_SECONDS) cleanedDelay + ONE_DAY_SECONDS else cleanedDelay;

                    switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = nowSecs + adjustedDelay })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_followees(nodeMem : Ver2.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                for (topic in GOVERNANCE_TOPICS.vals()) {
                    if (CacheManager.followee_changed(nodeMem, topic)) {
                        let neuron = NNS.Neuron({
                            nns_canister_id = NNS_CANISTER_ID;
                            neuron_id_or_subaccount = #NeuronId({
                                id = neuron_id;
                            });
                        });

                        let followeeToSet : Nat64 = switch (nodeMem.variables.followee) {
                            case (#Default) { DEFAULT_NEURON_FOLLOWEE };
                            case (#FolloweeId(followee)) { followee };
                        };

                        nodeMem.variables.followee := #FolloweeId(followeeToSet);

                        switch (await* neuron.follow({ topic = topic; followee = followeeToSet })) {
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

            public func update_dissolving(nodeMem : Ver2.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;

                if (CacheManager.dissolving_changed(nodeMem)) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    switch (nodeMem.variables.dissolve_status) {
                        case (#Dissolving) {
                            switch (await* neuron.startDissolving()) {
                                case (#ok(_)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Ok);
                                };
                                case (#err(err)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Err(debug_show err));
                                };
                            };
                        };
                        case (#Locked) {
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

            public func spawn_maturity(nodeMem : Ver2.NodeMem, vid : T.NodeId) : async* () {
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

            public func claim_maturity(nodeMem : Ver2.NodeMem, vec : T.NodeCoreMem) : async* () {
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

                        // send maturity to the maturity source
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

            public func disburse_neuron(nodeMem : Ver2.NodeMem, vec : T.NodeCoreMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;
                let ?dissolvingState = nodeMem.cache.state else return;
                let ?cachedStake = nodeMem.cache.cached_neuron_stake_e8s else return;

                let userWantsToDisburse = switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) { true };
                    case (#Locked) { false };
                };

                if (userWantsToDisburse and dissolvingState == NEURON_STATES.unlocked and cachedStake > 0) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    let ?account = core.getDestinationAccountIC(vec, 1) else return;

                    switch (await* neuron.disburse({ to_account = ?{ hash = Principal.toLedgerAccount(account.owner, account.subaccount) }; amount = null })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Err(debug_show err));
                        };
                    };
                };
            };

            public func refresh_voting_power(nodeMem : Ver2.NodeMem) : async* () {
                let ?neuron_id = nodeMem.cache.neuron_id else return;
                let ?votingPowerRefreshed = nodeMem.cache.voting_power_refreshed_timestamp_seconds else return;

                let nowSecs = U.now() / 1_000_000_000;

                if (nowSecs >= votingPowerRefreshed + TIMEOUT_REFRESH_VOTING_POWER_SECONDS) {
                    let neuron = NNS.Neuron({
                        nns_canister_id = NNS_CANISTER_ID;
                        neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
                    });

                    switch (await* neuron.refreshVotingPower()) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "refresh_voting_power", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "refresh_voting_power", #Err(debug_show err));
                        };
                    };
                };
            };

        };
    };
};
