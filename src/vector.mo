import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import N "./neuron";
import T "./types";
import { NNS } "mo:neuro";
import Node "mo:devefi/node";
import Tools "mo:neuro/tools";

module {

    public class NeuronVector({
        node_fee : Nat;
        canister_id : Principal;
        icp_ledger : Principal;
    }) {

        // async funcs get 1 minute do their work and then we try again
        let TIMEOUT_NANOS : Nat64 = (60 * 1_000_000_000);

        let MINIMUM_STAKE = 1_0000_0000;

        let ICP_GOVERNANCE = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        let nns = NNS.Governance({
            canister_id = canister_id;
            nns_canister_id = ICP_GOVERNANCE;
            icp_ledger_canister_id = icp_ledger;
        });

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
                            await* update_followee(nodeMem);
                            await* update_delay(nodeMem);
                            // await* add_hotkey(nodeMem);
                            // await* remove_hotkey(nodeMem);
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

        // Don't need to handle gov error here because if it's called again it will return ok result
        private func claim_neuron(nodeMem : N.Mem, nonce : Nat64) : async* () {
            switch (nodeMem.internals.claim_neuron) {
                case (#Init) {
                    nodeMem.internals.claim_neuron := #Calling(get_now_nanos());
                    
                    let #ok(neuronId) = await* nns.claimNeuron({ nonce = nonce }) else return;
                    nodeMem.internals.claim_neuron := #Done(neuronId);
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        nodeMem.internals.claim_neuron := #Calling(get_now_nanos());

                        let #ok(neuronId) = await* nns.claimNeuron({
                            nonce = nonce;
                        }) else return;

                        nodeMem.internals.claim_neuron := #Done(neuronId);
                    };
                };
                case _ { return };
            };
        };

        private func update_followee(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internals.claim_neuron else return;
            // TODO: follow topic 4 for governance
            // TODO: follow topic 14 for sns & community fund
            // follow 0 for all;

            switch (nodeMem.internals.update_followee) {
                case (#Init) {
                    let ?followee = nodeMem.variables.followee else return;

                    nodeMem.internals.update_followee := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    let #ok(_) = await* neuron.follow({
                        topic = 0;
                        followee = followee;
                    }) else return;

                    nodeMem.internals.update_followee := #Done(followee);
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        let ?followee = nodeMem.variables.followee else return;

                        nodeMem.internals.update_followee := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        let #ok(_) = await* neuron.follow({
                            topic = 0;
                            followee = followee;
                        }) else return;

                        nodeMem.internals.update_followee := #Done(followee);
                    };
                };
                case _ { return };
            };
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

            switch (nodeMem.internals.update_delay) {
                case (#Init) {
                    let ?dissolveTimestamp = nodeMem.variables.dissolve_timestamp_seconds else return

                    nodeMem.internals.update_delay := #Calling(get_now_nanos());

                    let neuron = NNS.Neuron({
                        nns_canister_id = ICP_GOVERNANCE;
                        neuron_id = neuronId;
                    });

                    let #ok(_) = await* neuron.setDissolveTimestamp({
                        dissolve_timestamp_seconds = dissolveTimestamp;
                    }) else return;

                    nodeMem.internals.update_delay := #Done(dissolveTimestamp);
                };
                case (#Calling(startTime)) {
                    if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
                        let ?dissolveTimestamp = nodeMem.variables.dissolve_timestamp_seconds else return

                        nodeMem.internals.update_delay := #Calling(get_now_nanos());

                        let neuron = NNS.Neuron({
                            nns_canister_id = ICP_GOVERNANCE;
                            neuron_id = neuronId;
                        });

                        let #ok(_) = await* neuron.setDissolveTimestamp({
                            dissolve_timestamp_seconds = dissolveTimestamp;
                        }) else return;

                        nodeMem.internals.update_delay := #Done(dissolveTimestamp);
                    };
                };
                case _ { return };
            };
        };

        // TODO figure out hotkey logic to accept an array of principals and add / remove as neccessary

        //     private func add_hotkey(nodeMem : N.Mem) : async* () {
        //         let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

        //         switch (nodeMem.internals.add_hotkey) {
        //             case (#Init) {
        //                 let ?hotkey = nodeMem.variables.hotkey else return

        //                 nodeMem.internals.add_hotkey := #Calling(get_now_nanos());

        //                 let neuron = NNS.Neuron({
        //                     nns_canister_id = ICP_GOVERNANCE;
        //                     neuron_id = neuronId;
        //                 });

        //                 let #ok(_) = await* neuron.addHotKey({
        //                     new_hot_key = hotkey;
        //                 }) else return;

        //                 nodeMem.internals.add_hotkey := #Done(hotkey);
        //             };
        //             case (#Calling(startTime)) {
        //                 if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
        //                     let ?hotkey = nodeMem.variables.hotkey else return;

        //                     nodeMem.internals.add_hotkey := #Calling(get_now_nanos());
        //                     let neuron = NNS.Neuron({
        //                         nns_canister_id = ICP_GOVERNANCE;
        //                         neuron_id = neuronId;
        //                     });

        //                     let #ok(_) = await* neuron.addHotKey({
        //                         new_hot_key = hotkey;
        //                     }) else return;

        //                     nodeMem.internals.add_hotkey := #Done(hotkey);
        //                 };
        //             };
        //             case _ { return };
        //         };
        //     };

        //     private func remove_hotkey(nodeMem : N.Mem) : async* () {
        //         let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

        //         switch (nodeMem.internals.remove_hotkey) {
        //             case (#Init) {
        //                 let ?hotkeyToRemove = nodeMem.variables.hotkey_to_remove else return

        //                 nodeMem.internals.remove_hotkey := #Calling(get_now_nanos());

        //                 let neuron = NNS.Neuron({
        //                     nns_canister_id = ICP_GOVERNANCE;
        //                     neuron_id = neuronId;
        //                 });

        //                 let #ok(_) = await* neuron.removeHotKey({
        //                     hot_key_to_remove = hotkeyToRemove;
        //                 }) else return;

        //                 nodeMem.internals.remove_hotkey := #Done(hotkeyToRemove);
        //             };
        //             case (#Calling(startTime)) {
        //                 if (get_now_nanos() - startTime >= TIMEOUT_NANOS) {
        //                     let ?hotkeyToRemove = nodeMem.variables.hotkey_to_remove else return

        //                     nodeMem.internals.remove_hotkey := #Calling(get_now_nanos());

        //                     let neuron = NNS.Neuron({
        //                         nns_canister_id = ICP_GOVERNANCE;
        //                         neuron_id = neuronId;
        //                     });

        //                     let #ok(_) = await* neuron.removeHotKey({
        //                         hot_key_to_remove = hotkeyToRemove;
        //                     }) else return;

        //                     nodeMem.internals.remove_hotkey := #Done(hotkeyToRemove);
        //                 };
        //             };
        //             case _ { return };
        //         };
        //     };
    };
};
