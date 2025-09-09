import Array "mo:base/Array";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Nat64 "mo:base/Nat64";
import Core "mo:devefi/core";
import U "mo:devefi/utils";
import Ver4 "../memory/v4";
import { NNS } "mo:neuro";
import Tools "mo:neuro/tools";
import Map "mo:map/Map";
import Nat32 "mo:base/Nat32";
import Blob "mo:base/Blob";
import NodeUtils "./node";
import CacheManager "./cache";
import Constants "../constants";
import GovTypes "mo:neuro/interfaces/nns_interface";

module {

    public type IcpNeuronNodeMem = Ver4.NodeMem;

    let T = Core.VectorModule;

    public class NeuronActions({
        nns : NNS.Governance;
        nodeMem : IcpNeuronNodeMem;
        vid : T.NodeId;
        vec : T.NodeCoreMem;
        core : Core.Mod;
    }) {

        public func refresh_cache() : async* () {
            if (not nodeMem.internals.neuron_claimed) return;

            let neuronNonces = Map.new<Blob, Nat64>();

            let mainNeuronNonce = NodeUtils.get_neuron_nonce(vid, 0);
            let mainNeuronSubaccount = Tools.computeNeuronSubaccountBytes(core.getThisCan(), mainNeuronNonce, #stake);

            let neuronSubs = Array.tabulate<{ subaccount : Blob }>(
                Nat32.toNat(nodeMem.internals.local_idx) + 1,
                func(idx : Nat) : { subaccount : Blob } {
                    let neuronNonce = NodeUtils.get_neuron_nonce(vid, Nat32.fromNat(idx));

                    let neuronSub = if (neuronNonce == mainNeuronNonce) {
                        mainNeuronSubaccount;
                    } else {
                        Tools.computeNeuronSubaccountBytes(core.getThisCan(), neuronNonce, #split);
                    };

                    ignore Map.put(neuronNonces, Map.bhash, neuronSub, neuronNonce);

                    return {
                        subaccount = neuronSub;
                    };
                },
            );

            let { full_neurons; neuron_infos } = await* nns.listNeurons({
                include_empty = false;
                include_public = false;
                include_readable = false;
                neuron_ids = [];
                neuron_subaccounts = ?neuronSubs;
                page_number = null;
                page_size = null;
            });

            let neuronInfos = Map.fromIter<Nat64, GovTypes.NeuronInfo>(neuron_infos.vals(), Map.n64hash);

            let neuronCache = Array.mapFilter<GovTypes.Neuron, Ver4.SharedNeuronCache>(
                full_neurons,
                func(full : GovTypes.Neuron) : ?Ver4.SharedNeuronCache {
                    let ?{ id } = full.id else return null;
                    let ?neuronNonce = Map.get(neuronNonces, Map.bhash, full.account) else return null;
                    let ?info = Map.get(neuronInfos, Map.n64hash, id) else return null;
                    
                    // Update the cache if this is the main neuron
                    if (neuronNonce == mainNeuronNonce) {
                        nodeMem.cache.neuron_id := ?id;
                        nodeMem.cache.nonce := ?neuronNonce;
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
                        nodeMem.cache.maturity_disbursements_in_progress := full.maturity_disbursements_in_progress;
                        nodeMem.cache.hot_keys := full.hot_keys;
                        nodeMem.cache.visibility := full.visibility;
                    };

                    return ?{
                        neuron_id = ?id;
                        nonce = ?neuronNonce;
                        maturity_e8s_equivalent = ?full.maturity_e8s_equivalent;
                        cached_neuron_stake_e8s = ?full.cached_neuron_stake_e8s;
                        created_timestamp_seconds = ?full.created_timestamp_seconds;
                        followees = full.followees;
                        dissolve_delay_seconds = ?info.dissolve_delay_seconds;
                        state = ?info.state;
                        voting_power = ?info.voting_power;
                        age_seconds = ?info.age_seconds;
                        voting_power_refreshed_timestamp_seconds = full.voting_power_refreshed_timestamp_seconds;
                        potential_voting_power = full.potential_voting_power;
                        deciding_voting_power = full.deciding_voting_power;
                        maturity_disbursements_in_progress = full.maturity_disbursements_in_progress;
                        hot_keys = full.hot_keys;
                        visibility = full.visibility;
                    };
                },
            );

            nodeMem.neuron_cache := neuronCache;
        };

        public func refresh_neuron() : async* () {
            let firstNonce = NodeUtils.get_neuron_nonce(vid, 0); // first localIdx for every neuron is always 0
            let ?{ cls = #icp(ledger) } = core.get_ledger_cls(Principal.fromText(Constants.ICP_LEDGER_CANISTER_ID)) else return;
            let ?refreshIdx = nodeMem.internals.refresh_idx else return;

            if (ledger.isSent(refreshIdx)) {
                switch (await* nns.claimNeuron({ nonce = firstNonce })) {
                    case (#ok(_)) {
                        nodeMem.internals.neuron_claimed := true;

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

        public func update_delay() : async* () {
            let ?neuron_id = CacheManager.delay_changed(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
                neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
            });

            let nowSecs = U.now() / 1_000_000_000;

            let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                case (#Default) { Constants.MINIMUM_DELAY_SECONDS };
                case (#DelayDays(days)) { days * Constants.ONE_DAY_SECONDS };
            };

            let cleanedDelay = Nat64.min(
                Nat64.max(delayToSet, Constants.MINIMUM_DELAY_SECONDS),
                Constants.MAXIMUM_DELAY_SECONDS,
            );

            // Store the original delay in nodeMem, keeping it at the max if applicable
            nodeMem.variables.dissolve_delay := #DelayDays(cleanedDelay / Constants.ONE_DAY_SECONDS);

            // give the maximum a buffer so we can reach 8 years
            let adjustedDelay = if (cleanedDelay == Constants.MAXIMUM_DELAY_SECONDS) cleanedDelay + Constants.ONE_DAY_SECONDS else cleanedDelay;

            switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = nowSecs + adjustedDelay })) {
                case (#ok(_)) {
                    NodeUtils.log_activity(nodeMem, "update_delay", #Ok);
                };
                case (#err(err)) {
                    NodeUtils.log_activity(nodeMem, "update_delay", #Err(debug_show err));
                };
            };
        };

        public func update_following() : async* () {
            let ?neuron_id = CacheManager.following_changed(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
                neuron_id_or_subaccount = #NeuronId({
                    id = neuron_id;
                });
            });

            let followeesToSet = switch (nodeMem.variables.followee) {
                case (#None) [];
                case (#Default) [{ id = Constants.DEFAULT_NEURON_FOLLOWEE }];
                case (#FolloweeId(followee)) [{ id = followee }];
            };

            let topicsToSet = Array.map(
                Constants.GOVERNANCE_TOPICS,
                func(topic : Int32) : {
                    topic : ?Int32;
                    followees : ?[{ id : Nat64 }];
                } {
                    {
                        topic = ?topic;
                        followees = ?followeesToSet;
                    };
                },
            );

            switch (await* neuron.setFollowing({ followeesForTopic = topicsToSet })) {
                case (#ok(_)) {
                    NodeUtils.log_activity(nodeMem, "update_following", #Ok);
                };
                case (#err(err)) {
                    NodeUtils.log_activity(nodeMem, "update_following", #Err(debug_show err));
                };
            };
        };

        public func update_dissolving() : async* () {
            let ?neuron_id = CacheManager.dissolving_changed(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
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

        public func disburse_maturity() : async* () {
            let ?neuron_id = CacheManager.maturity_ready(nodeMem) else return;

            // send maturity to the maturity source
            let ?{ owner; subaccount } = core.getSourceAccountIC(vec, 1) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
                neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
            });

            switch (await* neuron.disburseMaturity({ to_account_identifier = null; to_account = ?{ owner = ?owner; subaccount = subaccount }; percentage_to_disburse = 100 })) {
                case (#ok(_)) {
                    NodeUtils.log_activity(nodeMem, "disburse_maturity", #Ok);
                };
                case (#err(err)) {
                    NodeUtils.log_activity(nodeMem, "disburse_maturity", #Err(debug_show err));
                };
            };
        };

        public func disburse_neuron() : async* () {
            let ?neuron_id = CacheManager.neuron_ready_to_disburse(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
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

        public func update_hotkey() : async* () {
            let ?neuron_id = CacheManager.hotkeys_changed(nodeMem) else return;

            // Find the specific neuron in the cache
            let ?targetNeuron = Array.find(
                nodeMem.neuron_cache,
                func(neuron : Ver4.SharedNeuronCache) : Bool {
                    neuron.neuron_id == ?neuron_id;
                },
            ) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
                neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
            });

            // Remove all existing hotkeys
            for (hotkey in targetNeuron.hot_keys.vals()) {
                switch (await* neuron.removeHotKey({ hot_key_to_remove = hotkey })) {
                    case (#ok(_)) {
                        NodeUtils.log_activity(nodeMem, "remove_hotkey", #Ok);
                    };
                    case (#err(err)) {
                        NodeUtils.log_activity(nodeMem, "remove_hotkey", #Err(debug_show err));
                    };
                };
            };

            // Add the new hotkey if specified
            switch (nodeMem.variables.hotkey) {
                case (#None) {
                    // No hotkey to add, all existing hotkeys already removed
                };
                case (#HotkeyId(hotkeyToSet)) {
                    switch (await* neuron.addHotKey({ new_hot_key = hotkeyToSet })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "add_hotkey", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "add_hotkey", #Err(debug_show err));
                        };
                    };
                };
            };
        };

        public func update_visibility() : async* () {
            let ?neuron_id = CacheManager.visibility_changed(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
                neuron_id_or_subaccount = #NeuronId({ id = neuron_id });
            });

            let visibilityToSet : Int32 = switch (nodeMem.variables.visibility) {
                case (#Private) { 1 };
                case (#Public) { 2 };
            };

            switch (await* neuron.setVisibility({ visibility = visibilityToSet })) {
                case (#ok(_)) {
                    NodeUtils.log_activity(nodeMem, "update_visibility", #Ok);
                };
                case (#err(err)) {
                    NodeUtils.log_activity(nodeMem, "update_visibility", #Err(debug_show err));
                };
            };
        };

        public func refresh_voting_power() : async* () {
            let ?neuron_id = CacheManager.voting_power_stale(nodeMem) else return;

            let neuron = NNS.Neuron({
                nns_canister_id = Principal.fromText(Constants.NNS_CANISTER_ID);
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
