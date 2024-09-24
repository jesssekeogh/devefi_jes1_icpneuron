import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Blob "mo:base/Blob";
import T "./types";
import V "./vector";
import DeVeFi "mo:devefi";
import ICRC55 "mo:devefi/ICRC55";
import Node "mo:devefi/node";
import AccountIdentifier "mo:account-identifier";
import Hex "mo:encoding/Hex";
import { NNS } "mo:neuro";
import NTypes "mo:neuro/types";

actor class () = this {

    // Staking Vector Component
    // Stake neurons in vector nodes

    let ICP_LEDGER = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    let THIS_CANISTER = Principal.fromText("7cotl-6aaaa-aaaam-ade2q-cai");

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
            Node.DEFAULT_SETTINGS with
            ALLOW_TEMP_NODE_CREATION = true;
            PYLON_NAME = "NNS Vector";
            PYLON_GOVERNED_BY = "Neutrinite DAO";
        };
        toShared = T.toShared;
        sourceMap = T.sourceMap;
        destinationMap = T.destinationMap;
        createRequest2Mem = T.createRequest2Mem;
        modifyRequestMut = T.modifyRequestMut;
        getDefaults = T.getDefaults;
        meta = T.meta;
    });

    let vector = V.NeuronVector({
        node_fee = NODE_FEE;
        canister_id = THIS_CANISTER;
        icp_ledger = ICP_LEDGER;
    });

    /////////////////////////
    /// Main DeVeFi logic ///
    /////////////////////////

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () { vector.sync_cycle(nodes) },
    );

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () { await* vector.async_cycle(nodes) },
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
        nodes.start<system>(Principal.fromActor(this));
    };

    // ---------- Debug functions -----------

    public func get_neuron(id : Nat64) : async NTypes.NnsInformationResult {
        let neuron = NNS.Neuron({
            nns_canister_id = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
            neuron_id = id;
        });

        return await* neuron.getInformation();
    };

    public shared ({ caller }) func clear_mem() : () {
        assert (Principal.isController(caller));

        label vloop for ((vid, vec) in nodes.entries()) {
            switch (vec.custom) {
                case (#nns_neuron(nodeMem)) {
                    nodeMem.internals.claim_neuron := #Init;
                    nodeMem.internals.update_delay := #Init;
                    nodeMem.internals.start_dissolve := #Init;
                    nodeMem.internals.disburse_neuron := #Init;
                    nodeMem.internals.update_followees := #Init;
                    nodeMem.internals.spawn_maturity := #Init;
                    nodeMem.internals.claim_maturity := #Init;
                };
            };
        };
    };

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
