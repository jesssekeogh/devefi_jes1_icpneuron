import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import T "./types";
import A "./async";
import DeVeFi "mo:devefi";
import ICRC55 "mo:devefi/ICRC55";
import Node "mo:devefi/node";
import Tools "mo:neuro/tools";
import AccountIdentifier "mo:account-identifier";
import Hex "mo:encoding/Hex";

shared ({ caller = owner }) actor class VectorStaking() = this {

    // Staking Vector Component
    // Stake neurons in vector nodes

    /////////////////
    /// Constants ///
    /////////////////

    // async funcs get 1 minute do their work and then we try again
    let TIMEOUT_NANOS : Nat64 = (60 * 1_000_000_000);

    let MINIMUM_STAKE = 1_0000_0000;

    let ICP_GOVERNANCE = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let ICP_LEDGER = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    let NODE_FEE = 10_000;

    let supportedLedgers : [Principal] = [
        ICP_LEDGER
    ];

    /////////////////////
    /// Stable Memory ///
    /////////////////////

    // devefi ledger mem
    stable let dvf_mem = DeVeFi.Mem();

    let dvf = DeVeFi.DeVeFi<system>({ mem = dvf_mem });
    dvf.add_ledger<system>(supportedLedgers[0], #icp);

    // vector node mem
    stable let node_mem = Node.Mem<T.Mem>();
    let nodes = Node.Node<system, T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>({
        mem = node_mem;
        dvf;
        nodeCreateFee = func(_node) {
            {
                amount = NODE_FEE;
                ledger = ICP_LEDGER;
            };
        };
        supportedLedgers = Array.map<Principal, ICRC55.SupportedLedger>(supportedLedgers, func(x) = #ic(x));
        settings = {
            Node.DEFAULT_SETTINGS with ALLOW_TEMP_NODE_CREATION = true;
        };
        toShared = T.toShared;
        sourceMap = T.sourceMap;
        destinationMap = T.destinationMap;
        createRequest2Mem = T.createRequest2Mem;
        modifyRequestMut = T.modifyRequestMut;
        getDefaults = T.getDefaults;
        meta = T.meta;
    });

    /////////////////////////
    /// Main DeVeFi logic ///
    /////////////////////////

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () {
            label vloop for ((vid, vec) in nodes.entries()) {
                switch (vec.custom) {
                    case (#stake(nodeMem)) {
                        await A.generate_nonce(nodeMem, TIMEOUT_NANOS);
                        await A.claim_neuron(nodeMem, TIMEOUT_NANOS, dvf.me(), ICP_GOVERNANCE, ICP_LEDGER);
                        await A.update_followee(nodeMem, TIMEOUT_NANOS, ICP_GOVERNANCE);
                        await A.update_delay(nodeMem, TIMEOUT_NANOS, ICP_GOVERNANCE);
                        await A.add_hotkey(nodeMem, TIMEOUT_NANOS, ICP_GOVERNANCE);
                        await A.remove_hotkey(nodeMem, TIMEOUT_NANOS, ICP_GOVERNANCE);
                    };
                };
            };
        },
    );

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () {
            label vloop for ((vid, vec) in nodes.entries()) {

                if (not nodes.hasDestination(vec, 0)) continue vloop;
                let ?source = nodes.getSource(vec, 0) else continue vloop;

                let bal = source.balance();
                let ledger_fee = source.fee();
                if (bal <= NODE_FEE + ledger_fee) continue vloop;

                switch (vec.custom) {
                    case (#stake(nodeMem)) {
                        // If does not have a nonce we can't send ICP to it
                        let #Done(nonce) = nodeMem.internals.generate_nonce else continue vloop;

                        let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(dvf.me(), nonce);

                        source.send(#external_account({ owner = ICP_GOVERNANCE; subaccount = ?neuronSubaccount }), bal - NODE_FEE);

                        // TODO also check for maturity and spawn here
                    };
                };
            };
        },
    );

    public query func icrc55_get_nodefactory_meta() : async ICRC55.NodeFactoryMetaResp {
        nodes.icrc55_get_nodefactory_meta();
    };

    public query ({ caller }) func icrc55_create_node_get_fee(req : ICRC55.NodeRequest, creq : T.CreateRequest) : async ICRC55.NodeCreateFeeResp {
        nodes.icrc55_create_node_get_fee(caller, req, creq);
    };

    public shared ({ caller }) func icrc55_create_node(req : ICRC55.NodeRequest, creq : T.CreateRequest) : async Node.CreateNodeResp<T.Shared> {
        nodes.icrc55_create_node(caller, req, creq);
    };

    public query func icrc55_get_node(req : ICRC55.GetNode) : async ?Node.NodeShared<T.Shared> {
        nodes.icrc55_get_node(req);
    };

    public query ({ caller }) func icrc55_get_controller_nodes(req : ICRC55.GetControllerNodesRequest) : async [Node.NodeShared<T.Shared>] {
        nodes.icrc55_get_controller_nodes(caller, req);
    };

    public shared ({ caller }) func icrc55_set_controller_nodes(vid : ICRC55.LocalNodeId) : async ICRC55.DeleteNodeResp {
        nodes.icrc55_delete_node(caller, vid);
    };

    public shared ({ caller }) func icrc55_delete_node(vid : ICRC55.LocalNodeId) : async ICRC55.DeleteNodeResp {
        nodes.icrc55_delete_node(caller, vid);
    };

    public shared ({ caller }) func icrc55_modify_node(vid : ICRC55.LocalNodeId, req : ?ICRC55.NodeModifyRequest, creq : ?T.ModifyRequest) : async Node.ModifyNodeResp<T.Shared> {
        nodes.icrc55_modify_node(caller, vid, req, creq);
    };

    public query func icrc55_get_defaults(id : Text) : async T.CreateRequest {
        nodes.icrc55_get_defaults(id);
    };

    // We need to start the vector manually once when canister is installed, because we can't init dvf from the body
    // https://github.com/dfinity/motoko/issues/4384
    // Sending tokens before starting the canister for the first time wont get processed
    public shared ({ caller }) func start() {
        assert (Principal.isController(caller));
        dvf.start<system>(Principal.fromActor(this));
        nodes.setThisCanister(Principal.fromActor(this));
    };

    // ---------- Debug functions -----------

    public query func get_ledger_errors() : async [[Text]] {
        dvf.getErrors();
    };

    public query func get_ledgers_info() : async [DeVeFi.LedgerInfo] {
        dvf.getLedgersInfo();
    };

    // Dashboard explorer doesn't show icrc accounts in text format, this does
    // Hard to send tokens to Candid ICRC Accounts
    public query func get_node_addr(vid : Node.NodeId) : async ?Text {
        let ?(_, vec) = nodes.getNode(#id(vid)) else return null;

        let subaccount = Node.port2subaccount({
            vid;
            flow = #input;
            id = 0;
        });

        AccountIdentifier.accountIdentifier(Principal.fromActor(this), subaccount) |> Blob.toArray(_) |> ?Hex.encode(_);
    };

};
