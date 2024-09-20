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
                            await* update_delay(nodeMem);
                            await* update_followees(nodeMem);
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
                        // TODO once a day try spawn maturity and and disburse spawning neurons
                    };
                };
            };
        };

        private func get_now_nanos() : Nat64 {
            return Time.now() |> Int.abs(_) |> Nat64.fromNat(_);
        };

        private func should_call<T>(operation : N.OperationState<T>) : Bool {
            switch (operation) {
                case (#Init) {
                    return true;
                };
                case (#Calling(startTime)) {
                    return get_now_nanos() - startTime >= TIMEOUT_NANOS;
                };
                case (_) {
                    return false;
                };
            };
        };

        private func claim_neuron(nodeMem : N.Mem, nonce : Nat64) : async* () {
            if (should_call(nodeMem.internals.claim_neuron)) {
                nodeMem.internals.claim_neuron := #Calling(get_now_nanos());
                let #ok(neuronId) = await* nns.claimNeuron({ nonce = nonce }) else return;
                nodeMem.internals.claim_neuron := #Done({ neuron_id = neuronId });
            };
        };

        private func update_delay(nodeMem : N.Mem) : async* () {
            if (should_call(nodeMem.internals.update_delay)) {
                let #Done({ neuron_id }) = nodeMem.internals.claim_neuron else return;
                let ?dissolveTimestamp = nodeMem.variables.delay_timestamp_seconds else return

                nodeMem.internals.update_delay := #Calling(get_now_nanos());

                let neuron = NNS.Neuron({
                    nns_canister_id = ICP_GOVERNANCE;
                    neuron_id = neuron_id;
                });

                // TODO check here if an error can return "already set"
                let #ok(_) = await* neuron.setDissolveTimestamp({
                    dissolve_timestamp_seconds = dissolveTimestamp;
                }) else return;

                nodeMem.internals.update_delay := #Done({
                    delay_timestamp = dissolveTimestamp;
                });
            };
        };

        private func start_dissolve(nodeMem : N.Mem) : async* () {
            if (should_call(nodeMem.internals.start_dissolve)) {
                let #Done({ neuron_id }) = nodeMem.internals.claim_neuron else return;
                let ?dissolve = nodeMem.variables.start_dissolve else return;
                if (not dissolve) return;

                nodeMem.internals.start_dissolve := #Calling(get_now_nanos());

                let neuron = NNS.Neuron({
                    nns_canister_id = ICP_GOVERNANCE;
                    neuron_id = neuron_id;
                });

                // TODO check here if an error can return "already dissolve"
                let #ok(_) = await* neuron.startDissolving() else return;

                nodeMem.internals.start_dissolve := #Done({
                    timestamp = get_now_nanos();
                });
            };
        };

        private func disburse_neuron(nodeMem : N.Mem, refund : Node.Endpoint) : async* () {
            if (should_call(nodeMem.internals.disburse_neuron)) {
                let #Done({ neuron_id }) = nodeMem.internals.claim_neuron else return;
                let ?disburse = nodeMem.variables.disburse_neuron else return;
                if (not disburse) return;

                nodeMem.internals.disburse_neuron := #Calling(get_now_nanos());

                let neuron = NNS.Neuron({
                    nns_canister_id = ICP_GOVERNANCE;
                    neuron_id = neuron_id;
                });

                let #ic(endpoint) = refund else return;

                // TODO check if error can return "already disbursed"
                let #ok(_) = await* neuron.disburse({
                    to_account = ?{
                        hash = AccountIdentifier.accountIdentifier(endpoint.account.owner, Option.get(endpoint.account.subaccount, AccountIdentifier.defaultSubaccount())) |> Blob.toArray(_);
                    };
                    amount = null;
                }) else return;

                nodeMem.internals.disburse_neuron := #Done({
                    neuron_id = neuron_id;
                });
            };
        };

        // Changing followees requires updating followee variable and setting #Init
        private func update_followees(nodeMem : N.Mem) : async* () {
            if (should_call(nodeMem.internals.update_followees)) {
                let #Done({ neuron_id }) = nodeMem.internals.claim_neuron else return;
                let ?followeeToSet = nodeMem.variables.followee else return;

                nodeMem.internals.update_followees := #Calling(get_now_nanos());

                let expectedFollowees : [{ topic : Int32; followee : Nat64 }] = [
                    { topic = 0; followee = followeeToSet }, // Catch all
                    { topic = 4; followee = followeeToSet }, // Governance
                    { topic = 14; followee = followeeToSet }, // SNS & Community Fund
                ];

                let neuron = NNS.Neuron({
                    nns_canister_id = ICP_GOVERNANCE;
                    neuron_id = neuron_id;
                });

                for (followee in expectedFollowees.vals()) {
                    let #ok(_) = await* neuron.follow(followee) else return;
                };

                nodeMem.internals.update_followees := #Done({
                    neuron_id = followeeToSet;
                });
            };
        };
    };
};
