import Principal "mo:base/Principal";
import Nat64 "mo:base/Nat64";
import Node "mo:devefi/node";
import Tools "mo:neuro/tools";
import { NNS } "mo:neuro";
import T "./types";

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

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L41
        let GOVERNANCE_TOPICS : [Int32] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18];

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
                        // TODO refresh neuron after send
                    };
                };
            };
        };

        public func async_cycle(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {};
                };
            };
        };

        public func update_cache(nodes : Node.Node<T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>) : async* () {
            let { full_neurons } = await* nns.listNeurons({
                neuronIds = [];
                readable = true;
            });

            // update every neurons cache
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#nns_neuron(nodeMem)) {};
                };
            };

            ignore full_neurons;
        };

    };

};
