import Principal "mo:base/Principal";
import Timer "mo:base/Timer";
import T "./types";
import V "./vector";
import DeVeFi "mo:devefi";
import ICRC55 "mo:devefi/ICRC55";
import Node "mo:devefi/node";

shared ({ caller = owner }) actor class NNSVECTOR ({
    icp_governance : Principal;
    icp_ledger : Principal;
    fee_ledger : Principal;
}) = this {

    let supportedLedgers : [Principal] = [
        icp_ledger,
        fee_ledger,
    ];

    stable let dvf_mem = DeVeFi.Mem();

    let dvf = DeVeFi.DeVeFi<system>({ mem = dvf_mem });
    dvf.add_ledger<system>(supportedLedgers[0], #icp);
    dvf.add_ledger<system>(supportedLedgers[1], #icrc);

    stable let node_mem = Node.Mem<T.Mem>();
    let nodes = Node.Node<system, T.CreateRequest, T.Mem, T.Shared, T.ModifyRequest>({
        mem = node_mem;
        dvf;
        settings = {
            Node.DEFAULT_SETTINGS with
            ALLOW_TEMP_NODE_CREATION = true;
            MAX_SOURCES = 1 : Nat8;
            MAX_DESTINATIONS = 1 : Nat8;
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
        nodeMeta = T.nodeMeta;
    });

    var vector : ?V.NeuronVector = null;

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () { ignore do ? { vector!.sync_cycle(nodes) } },
    );

    ignore Timer.recurringTimer<system>(
        #seconds(3),
        func() : async () { ignore do ? { await* vector!.async_cycle(nodes) } },
    );

    ignore Timer.recurringTimer<system>(
        #seconds(60),
        func() : async () { ignore do ? { await* vector!.cache_cycle(nodes) } },
    );

    public query func icrc55_get_pylon_meta() : async ICRC55.NodeFactoryMetaResp {
        nodes.icrc55_get_pylon_meta();
    };

    public shared ({ caller }) func icrc55_command(cmds : [ICRC55.Command<T.CreateRequest, T.ModifyRequest>]) : async [ICRC55.CommandResponse<T.Shared>] {
        nodes.icrc55_command(caller, cmds);
    };

    public query func icrc55_get_nodes(req : [ICRC55.GetNode]) : async [?Node.NodeShared<T.Shared>] {
        nodes.icrc55_get_nodes(req);
    };

    public query ({ caller }) func icrc55_get_controller_nodes(req : ICRC55.GetControllerNodesRequest) : async [Node.NodeShared<T.Shared>] {
        nodes.icrc55_get_controller_nodes(caller, req);
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
        vector := do ? {
            V.NeuronVector({
                canister_id = Principal.fromActor(this);
                icp_ledger = icp_ledger;
                icp_ledger_cls = dvf.get_ledger(icp_ledger)!;
                icp_governance = icp_governance;
            });
        };
    };

    // ---------- Debug functions -----------

    public query func get_ledger_errors() : async [[Text]] {
        dvf.getErrors();
    };

    public query func get_ledgers_info() : async [DeVeFi.LedgerInfo] {
        dvf.getLedgersInfo();
    };

};
