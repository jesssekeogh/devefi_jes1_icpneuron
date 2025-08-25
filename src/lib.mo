import MU "mo:mosup";
import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Error "mo:base/Error";
import Array "mo:base/Array";
import Core "mo:devefi/core";
import Ver1 "./memory/v1";
import Ver2 "./memory/v2";
import Ver3 "./memory/v3";
import Ver4 "./memory/v4";
import I "./interface";
import { NNS } "mo:neuro";
import Tools "mo:neuro/tools";
import NodeUtils "./modules/node";
import { NeuronActions } "./modules/neuron";
import {
    ICP_LEDGER_CANISTER_ID;
    NNS_CANISTER_ID;
    MINIMUM_STAKE;
} "./constants";

module {
    let T = Core.VectorModule;

    public let Interface = I;

    public module Mem {
        public module Vector {
            public let V1 = Ver1;
            public let V2 = Ver2;
            public let V3 = Ver3;
            public let V4 = Ver4;
        };
    };

    let M = Mem.Vector.V4;

    public let ID = "devefi_jes1_icpneuron";

    public class Mod({
        xmem : MU.MemShell<M.Mem>;
        core : Core.Mod;
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        public type IcpNeuronNodeMem = Ver4.NodeMem;

        let nns = NNS.Governance({
            canister_id = core.getThisCan();
            nns_canister_id = NNS_CANISTER_ID();
            icp_ledger_canister_id = ICP_LEDGER_CANISTER_ID();
        });

        public func meta() : T.Meta {
            {
                id = ID; // This has to be same as the variant in vec.custom
                name = "ICP Neuron";
                author = "jes1";
                description = "Stake ICP neurons and receive maturity directly to your destination";
                supported_ledgers = [#ic(ICP_LEDGER_CANISTER_ID())];
                version = #beta([0, 4, 0]);
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
                        cost_per_day = 3_1700_0000; // 3.17 NTN
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

        public func vote({
            vid : T.NodeId;
            neuronId : Nat64;
            proposal : Nat64;
            vote : Int32;
        }) : async* T.Modify {
            let ?nodeMem = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            // Validate that the neuronId exists in the node's neuron_cache
            let neuronExists = Array.find<Ver4.SharedNeuronCache>(
                nodeMem.neuron_cache,
                func(cachedNeuron : Ver4.SharedNeuronCache) : Bool {
                    switch (cachedNeuron.neuron_id) {
                        case (?id) { id == neuronId };
                        case (null) { false };
                    };
                },
            );

            let ?_ = neuronExists else return #err("Neuron ID " # debug_show neuronId # " not found in node's neuron cache");

            let neuron = NNS.Neuron({
                nns_canister_id = NNS_CANISTER_ID();
                neuron_id_or_subaccount = #NeuronId({ id = neuronId });
            });

            switch (await* neuron.registerVote({ proposal = proposal; vote = vote })) {
                case (#ok(())) {
                    NodeUtils.log_activity(nodeMem, "vote", #Ok(()));
                    return #ok();
                };
                case (#err(err)) {
                    NodeUtils.log_activity(nodeMem, "vote", #Err(debug_show err));
                    return #err("Failed to register vote: " # debug_show err);
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
                let requiredStake = if (Option.isSome(nodeMem.cache.neuron_id)) core.Source.fee(sourceStake) else MINIMUM_STAKE();

                if (stakeBal > requiredStake) {
                    // Proceed to send ICP to the neuron's subaccount
                    let #ok(intent) = core.Source.Send.intent(
                        sourceStake,
                        #external_account(#icrc({ owner = NNS_CANISTER_ID(); subaccount = ?neuronSubaccount })),
                        stakeBal,
                        null,
                    ) else return;

                    let txId = core.Source.Send.commit(intent);

                    // Set refresh_idx to refresh or claim the neuron in the next round
                    NodeUtils.tx_sent(nodeMem, txId);
                };

                // forward all maturity
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;
                let maturityBal = core.Source.balance(sourceMaturity);

                if (maturityBal > core.Source.fee(sourceMaturity)) {
                    // if cost per day billing option chosen, send maturity with no tx fee
                    let maturityDestination = switch (vec.billing.billing_option) {
                        case (1) {
                            let ?account = core.getDestinationAccountIC(vec, 0) else return;
                            #external_account(#icrc({ owner = account.owner; subaccount = account.subaccount }));
                        };
                        case (_) { #destination({ port = 0 }) };
                    };

                    let #ok(intent) = core.Source.Send.intent(
                        sourceMaturity,
                        maturityDestination,
                        maturityBal,
                        null,
                    ) else return;

                    ignore core.Source.Send.commit(intent);
                };
            };

            public func singleAsync(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : M.NodeMem) : async* () {
                try {
                    let neuron = NeuronActions({
                        nns = nns;
                        nodeMem = nodeMem;
                        vid = vid;
                        vec = vec;
                        core = core;
                    });

                    await* neuron.refresh_neuron();
                    await* neuron.update_delay();
                    await* neuron.update_following();
                    await* neuron.update_dissolving();
                    await* neuron.disburse_maturity();
                    await* neuron.disburse_neuron();
                    await* neuron.refresh_voting_power();
                    await* neuron.update_hotkeys();
                    await* neuron.update_visibility();
                    await* neuron.refresh_cache();
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
                    var hotkeys = t.variables.hotkeys;
                    var visibility = t.variables.visibility;
                };
                internals = {
                    var updating = #Init;
                    var local_idx = 0;
                    var refresh_idx = null;
                    var neuron_claimed = false;
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
                    var maturity_disbursements_in_progress = null;
                    var hot_keys = [];
                    var visibility = null;
                };
                var neuron_cache = [];
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
            t.variables.hotkeys := Option.get(m.hotkeys, t.variables.hotkeys);
            t.variables.visibility := Option.get(m.visibility, t.variables.visibility);
            #ok();
        };

        public func get(vid : T.NodeId, _vec : T.NodeCoreMem) : T.Get<I.Shared> {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            #ok {
                variables = {
                    dissolve_delay = t.variables.dissolve_delay;
                    dissolve_status = t.variables.dissolve_status;
                    followee = t.variables.followee;
                    hotkeys = t.variables.hotkeys;
                    visibility = t.variables.visibility;
                };
                internals = {
                    updating = t.internals.updating;
                    local_idx = t.internals.local_idx;
                    refresh_idx = t.internals.refresh_idx;
                    neuron_claimed = t.internals.neuron_claimed;
                    spawning_neurons = []; // deprecated now
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
                    maturity_disbursements_in_progress = t.cache.maturity_disbursements_in_progress;
                    hot_keys = t.cache.hot_keys;
                    visibility = t.cache.visibility;
                };
                neuron_cache = t.neuron_cache;
                log = t.log;
            };
        };

        public func defaults() : I.CreateRequest {
            {
                variables = {
                    dissolve_delay = #Default;
                    dissolve_status = #Locked;
                    followee = #Default;
                    hotkeys = #None;
                    visibility = #Private;
                };
            };
        };

        public func sources(_id : T.NodeId) : T.Endpoints {
            [(0, "Stake"), (0, "_Maturity")];
        };

        public func destinations(_id : T.NodeId) : T.Endpoints {
            [(0, "Maturity"), (0, "Disburse")];
        };

    };
};