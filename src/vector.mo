import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import N "./neuron";
import T "./types";
import { NNS } "mo:neuro";
import Node "mo:devefi/node";
import Tools "mo:neuro/tools";
import AccountIdentifier "mo:account-identifier";

module {

    public class NeuronVector({
        node_fee : Nat;
        canister_id : Principal;
        icp_ledger : Principal;
    }) {

        // async funcs get 1 minute do their work and then we try again
        let TIMEOUT_NANOS : Nat64 = (60 * 1_000_000_000);

        let ICP_GOVERNANCE = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        let nns = NNS.Governance({
            canister_id = canister_id;
            nns_canister_id = ICP_GOVERNANCE;
            icp_ledger_canister_id = icp_ledger;
        });

        ////////////////////
        /// Vector Cycle ///
        ////////////////////

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
                        source.send(#external_account({ owner = ICP_GOVERNANCE; subaccount = ?neuronSubaccount }), bal - node_fee);

                        // TODO refresh the neurons balances after transfers,
                        // cant be called here because the transfer can occur after the refresh
                    };
                };
            };
        };

        public func async_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {
                        try {
                            await* claim_neuron(nodeMem, Nat64.fromNat32(vid));

                            // configs:
                            await* update_delay(nodeMem);
                            await* update_followees(nodeMem);
                            await* update_hotkey(nodeMem);
                            await* start_dissolve(nodeMem);
                            await* disburse_neuron(nodeMem, vec.refund[0]); // TODO disburse to another output?
                        } catch (error) {
                            // TODO log errors
                        };
                    };
                };
            };
        };

        public func maturity_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {

                        // TODO once a week try spawn maturity and and disburse spawning neurons, set to 7 days (takes 7 days to spawn neurons)
                    };
                };
            };
        };

        private func get_now_nanos() : Nat64 {
            return Time.now() |> Int.abs(_) |> Nat64.fromNat(_);
        };

        ///////////////////////////
        /// Lifecycle functions ///
        ///////////////////////////

        private func claim_neuron(nodeMem : N.Mem, nonce : Nat64) : async* () {
            switch (nodeMem.internal_lifecycle.claim_neuron) {
                case (#Init) {
                    nodeMem.internal_lifecycle.claim_neuron := #Calling(get_now_nanos());

                    // there is no "already set" error here, just returns ok again
                    let #ok(neuronId) = await* nns.claimNeuron({ nonce = nonce }) else return;
                    nodeMem.internal_lifecycle.claim_neuron := #Done(neuronId);
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        nodeMem.internal_lifecycle.claim_neuron := #Calling(get_now_nanos());

                        let #ok(neuronId) = await* nns.claimNeuron({
                            nonce = nonce;
                        }) else return;

                        nodeMem.internal_lifecycle.claim_neuron := #Done(neuronId);
                    };
                };
                case _ { return };
            };
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internal_lifecycle.claim_neuron else return;

            switch (nodeMem.internal_lifecycle.update_delay) {
                case (#Init) {
                    let ?dissolveTimestamp = nodeMem.variables.delay_timestamp_seconds else return

                    nodeMem.internal_lifecycle.update_delay := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    let #ok(_) = await* neuron.setDissolveTimestamp({
                        dissolve_timestamp_seconds = dissolveTimestamp;
                    }) else return;

                    nodeMem.internal_lifecycle.update_delay := #Done(dissolveTimestamp);
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        let ?dissolveTimestamp = nodeMem.variables.delay_timestamp_seconds else return

                        nodeMem.internal_lifecycle.update_delay := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        // TODO check here if an error can return "already set"
                        let #ok(_) = await* neuron.setDissolveTimestamp({
                            dissolve_timestamp_seconds = dissolveTimestamp;
                        }) else return;

                        nodeMem.internal_lifecycle.update_delay := #Done(dissolveTimestamp);
                    };
                };
                case _ { return };
            };
        };

        private func start_dissolve(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internal_lifecycle.claim_neuron else return;
            if (not nodeMem.variables.start_dissolve) return;

            switch (nodeMem.internal_lifecycle.start_dissolve) {
                case (#Init) {
                    nodeMem.internal_lifecycle.start_dissolve := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    // TODO check here if an error can return "already set"
                    let #ok(_) = await* neuron.startDissolving() else return;

                    nodeMem.internal_lifecycle.start_dissolve := #Done(get_now_nanos());
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        nodeMem.internal_lifecycle.start_dissolve := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        let #ok(_) = await* neuron.startDissolving() else return;

                        nodeMem.internal_lifecycle.start_dissolve := #Done(get_now_nanos());
                    };
                };
                case _ { return };
            };
        };

        private func disburse_neuron(nodeMem : N.Mem, refund : Node.Endpoint) : async* () {
            let #Done(neuronId) = nodeMem.internal_lifecycle.claim_neuron else return;
            if (not nodeMem.variables.disburse_neuron) return;

            switch (nodeMem.internal_lifecycle.disburse_neuron) {
                case (#Init) {
                    nodeMem.internal_lifecycle.disburse_neuron := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    let #ic(endpoint) = refund else return;

                    let #ok(_) = await* neuron.disburse({
                        to_account = ?{
                            hash = AccountIdentifier.accountIdentifier(endpoint.account.owner, Option.get(endpoint.account.subaccount, AccountIdentifier.defaultSubaccount())) |> Blob.toArray(_);
                        };
                        amount = null;
                    }) else return;

                    nodeMem.internal_lifecycle.disburse_neuron := #Done(get_now_nanos());
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        nodeMem.internal_lifecycle.disburse_neuron := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        let #ic(endpoint) = refund else return;

                        let #ok(_) = await* neuron.disburse({
                            to_account = ?{
                                hash = AccountIdentifier.accountIdentifier(endpoint.account.owner, Option.get(endpoint.account.subaccount, AccountIdentifier.defaultSubaccount())) |> Blob.toArray(_);
                            };
                            amount = null;
                        }) else return;
                        
                        nodeMem.internal_lifecycle.disburse_neuron := #Done(get_now_nanos());
                    };
                };
                case _ { return };
            };
        };

        ///////////////////////////////////
        /// Internal followee functions ///
        ///////////////////////////////////

        // Changing followees requires updating followee variable and setting #Init
        private func update_followees(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internal_lifecycle.claim_neuron else return;
            let ?followeeToSet = nodeMem.variables.followee else return;

            switch (nodeMem.internal_followees.update_followees) {
                case (#Init) {
                    let missingFollowees = getMissingFollowees(followeeToSet, nodeMem.internal_followees.cached_followees);

                    if (missingFollowees.size() > 0) {
                        nodeMem.internal_followees.update_followees := #Calling(get_now_nanos());

                        // we have a new followee to set so clear cache:
                        nodeMem.internal_followees.cached_followees := [];

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        // there is no "already set" error here, just returns ok again
                        let #ok(_) = await* neuron.follow(missingFollowees[0]) else return;

                        // Prevent duplicates before appending
                        if (not isInFolloweeCache(missingFollowees[0], nodeMem.internal_followees.cached_followees)) {
                            nodeMem.internal_followees.cached_followees := Array.append(
                                nodeMem.internal_followees.cached_followees,
                                [missingFollowees[0]],
                            );
                        };
                    } else {
                        // if no misssing followees, it's done
                        nodeMem.internal_followees.update_followees := #Done(followeeToSet);
                    };
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {

                        let missingFollowees = getMissingFollowees(followeeToSet, nodeMem.internal_followees.cached_followees);

                        if (missingFollowees.size() > 0) {
                            nodeMem.internal_followees.update_followees := #Calling(get_now_nanos());

                            let neuron = NNS.Neuron({
                                nns_canister_id = ICP_GOVERNANCE;
                                neuron_id = neuronId;
                            });

                            let #ok(_) = await* neuron.follow(missingFollowees[0]) else return;

                            // Prevent duplicates before appending
                            if (not isInFolloweeCache(missingFollowees[0], nodeMem.internal_followees.cached_followees)) {
                                nodeMem.internal_followees.cached_followees := Array.append(
                                    nodeMem.internal_followees.cached_followees,
                                    [missingFollowees[0]],
                                );
                            };
                        } else {
                            nodeMem.internal_followees.update_followees := #Done(followeeToSet);
                        };
                    };
                };
                case _ { return };
            };
        };

        private func getMissingFollowees(followeeToSet : N.NeuronId, cache : [N.TopicFollowee]) : [N.TopicFollowee] {
            return Array.filter<N.TopicFollowee>(
                getExpectedFollowees(followeeToSet),
                func(followee) : Bool {
                    not isInFolloweeCache(followee, cache);
                },
            );
        };

        private func getExpectedFollowees(followeeToSet : N.NeuronId) : [N.TopicFollowee] {
            return [
                { topic = 0; followee = followeeToSet }, // Catch all
                { topic = 4; followee = followeeToSet }, // Governance
                { topic = 14; followee = followeeToSet }, // SNS & Community Fund
            ];
        };

        private func isInFolloweeCache(followee : N.TopicFollowee, cache : [N.TopicFollowee]) : Bool {
            return Option.isSome(
                Array.find<N.TopicFollowee>(
                    cache,
                    func(cachedFollowee) : Bool {
                        cachedFollowee.topic == followee.topic and cachedFollowee.followee == followee.followee
                    },
                )
            );
        };

        /////////////////////////////////
        /// Internal hotkey functions ///
        /////////////////////////////////

        // Changing hotkey requires updating hotkey variable and setting #Init
        private func update_hotkey(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internal_lifecycle.claim_neuron else return;
            let ?hotkeyToSet = nodeMem.variables.hotkey else return;

            switch (nodeMem.internal_hotkey.update_hotkey) {
                case (#Init) {
                    nodeMem.internal_hotkey.update_hotkey := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    switch (nodeMem.internal_hotkey.cached_hotkey) {
                        case (?cachedHotkey) {
                            // cache updated (old followee var removed) so remove and clear cache
                            if (hotkeyToSet != cachedHotkey) {
                                switch (await* neuron.removeHotKey({ hot_key_to_remove = cachedHotkey })) {
                                    case (#ok(_)) {
                                        nodeMem.internal_hotkey.cached_hotkey := null;
                                    };
                                    case (#err(error)) {
                                        let ?err = error else return;

                                        if (err.error_type == 9) {
                                            // already done
                                            nodeMem.internal_hotkey.cached_hotkey := null;
                                        };
                                    };
                                };
                            };
                        };
                        case _ {
                            switch (await* neuron.addHotKey({ new_hot_key = hotkeyToSet })) {
                                case (#ok(_)) {
                                    nodeMem.internal_hotkey.cached_hotkey := ?hotkeyToSet;
                                    nodeMem.internal_hotkey.update_hotkey := #Done(hotkeyToSet);
                                };
                                case (#err(error)) {
                                    let ?err = error else return;

                                    if (err.error_type == 9) {
                                        nodeMem.internal_hotkey.cached_hotkey := ?hotkeyToSet;
                                        nodeMem.internal_hotkey.update_hotkey := #Done(hotkeyToSet);
                                    };
                                };
                            };
                        };
                    };

                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        nodeMem.internal_hotkey.update_hotkey := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        switch (nodeMem.internal_hotkey.cached_hotkey) {
                            case (?cachedHotkey) {
                                if (hotkeyToSet != cachedHotkey) {
                                    switch (await* neuron.removeHotKey({ hot_key_to_remove = cachedHotkey })) {
                                        case (#ok(_)) {
                                            nodeMem.internal_hotkey.cached_hotkey := null;
                                        };
                                        case (#err(error)) {
                                            let ?err = error else return;

                                            if (err.error_type == 9) {
                                                // already done
                                                nodeMem.internal_hotkey.cached_hotkey := null;
                                            };
                                        };
                                    };
                                };
                            };
                            case _ {
                                switch (await* neuron.addHotKey({ new_hot_key = hotkeyToSet })) {
                                    case (#ok(_)) {
                                        nodeMem.internal_hotkey.cached_hotkey := ?hotkeyToSet;
                                        nodeMem.internal_hotkey.update_hotkey := #Done(hotkeyToSet);
                                    };
                                    case (#err(error)) {
                                        let ?err = error else return;

                                        if (err.error_type == 9) {
                                            nodeMem.internal_hotkey.cached_hotkey := ?hotkeyToSet;
                                            nodeMem.internal_hotkey.update_hotkey := #Done(hotkeyToSet);
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                case _ { return };
            };
        };

    };
};
