import Principal "mo:base/Principal";
import DeVeFi "mo:devefi";
import ICRC55 "mo:devefi/ICRC55";
import Rechain "mo:rechain";
import RT "./rechain";
import Timer "mo:base/Timer";
import U "mo:devefi/utils";
import T "./vector_modules";
import MU_sys "mo:devefi/sys";

import VecNNS "../../src";
import Core "mo:devefi/core";

shared ({ caller = owner }) actor class NNSVECTOR() = this {

    stable let chain_mem = Rechain.Mem();

    var chain = Rechain.Chain<RT.DispatchAction, RT.DispatchActionError>({
        settings = ?{
            Rechain.DEFAULT_SETTINGS with supportedBlocks = [{
                block_type = "55vec";
                url = "https://github.com/dfinity/ICRC/issues/55";
            }];
        };
        mem = chain_mem;
        encodeBlock = RT.encodeBlock;
        reducers = [];
    });

    ignore Timer.setTimer<system>(
        #seconds 0,
        func() : async () {
            await chain.start_timers<system>();
        },
    );

    ignore Timer.setTimer<system>(
        #seconds 1,
        func() : async () {
            await chain.upgrade_archives();
        },
    );

    stable let dvf_mem = DeVeFi.Mem();

    let dvf = DeVeFi.DeVeFi<system>({ mem = dvf_mem });

    stable let mem_core_1 = Core.Mem.Core.V1.new();

    let test_icrc : Principal = Principal.fromText("7tjcv-pp777-77776-qaaaa-cai");
    let icp_ledger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    let billing : ICRC55.BillingPylon = {
        ledger = test_icrc; // TODO remove and use real: f54if-eqaaa-aaaaq-aacea-cai
        min_create_balance = 3000000;
        operation_cost = 1000;
        freezing_threshold_days = 10;
        exempt_daily_cost_balance = null;
        split = {
            platform = 200;
            pylon = 200;
            author = 400;
            affiliate = 200;
        };
    };
    let core = Core.Mod<system>({
        xmem = mem_core_1;
        settings = {
            Core.DEFAULT_SETTINGS with
            BILLING = ?billing;
            PYLON_NAME = "NNS Vector";
            PYLON_GOVERNED_BY = "Neutrinite DAO";
            PYLON_FEE_ACCOUNT = ?{
                owner = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
                subaccount = null;
            };
        };
        dvf;
        chain;
    });

    dvf.add_ledger<system>(test_icrc, #icrc);
    dvf.add_ledger<system>(icp_ledger, #icp);

    dvf.start<system>(Principal.fromActor(this));
    core.start<system>(Principal.fromActor(this));
    chain_mem.canister := ?Principal.fromActor(this);

    // Components
    let mem_vec_nns_1 = VecNNS.Mem.Vector.V1.new();
    let vec_nns = VecNNS.Mod({ xmem = mem_vec_nns_1; core; dvf });

    let vmod = T.VectorModules({ vec_nns });

    let sys = MU_sys.Mod<system, T.CreateRequest, T.Shared, T.ModifyRequest>({
        xmem = mem_core_1;
        dvf;
        core;
        vmod;
    });

    private func proc() {
        label vloop for ((vid, vec) in core.entries()) {
            if (not vec.active) continue vloop;
            if (not core.hasDestination(vec, 0)) continue vloop;
            switch (vec.module_id) {
                case ("nns") { vec_nns.run(vid, vec) };
                case (_) { continue vloop };
            };
        };
    };

    private func async_proc() : async* () {
        label vloop for ((vid, vec) in core.entries()) {
            if (not vec.active) continue vloop;
            if (not core.hasDestination(vec, 0)) continue vloop;
            switch (vec.module_id) {
                case ("nns") { await* vec_nns.runAsync(vid, vec) };
                case (_) { continue vloop };
            };
        };
    };

    ignore Timer.recurringTimer<system>(
        #seconds 2,
        func() : async () {
            core.heartbeat(proc);
        },
    );

    ignore Timer.recurringTimer<system>(
        #seconds 2,
        func() : async () {
            await* async_proc();
        },
    );

    // ICRC-55

    public query func icrc55_get_pylon_meta() : async ICRC55.PylonMetaResp {
        sys.icrc55_get_pylon_meta();
    };

    public shared ({ caller }) func icrc55_command(req : ICRC55.BatchCommandRequest<T.CreateRequest, T.ModifyRequest>) : async ICRC55.BatchCommandResponse<T.Shared> {
        sys.icrc55_command<RT.DispatchActionError>(
            caller,
            req,
            func(r) {
                chain.dispatch({
                    caller;
                    payload = #vector(r);
                    ts = U.now();
                });
            },
        );
    };

    public query func icrc55_get_nodes(req : [ICRC55.GetNode]) : async [?MU_sys.NodeShared<T.Shared>] {
        sys.icrc55_get_nodes(req);
    };

    public query ({ caller }) func icrc55_get_controller_nodes(req : ICRC55.GetControllerNodesRequest) : async [MU_sys.NodeShared<T.Shared>] {
        sys.icrc55_get_controller_nodes(caller, req);
    };

    public query func icrc55_get_defaults(id : Text) : async T.CreateRequest {
        sys.icrc55_get_defaults(id);
    };

    public query ({ caller }) func icrc55_virtual_balances(req : ICRC55.VirtualBalancesRequest) : async ICRC55.VirtualBalancesResponse {
        sys.icrc55_virtual_balances(caller, req);
    };

    // ICRC-3

    public query func icrc3_get_blocks(args : Rechain.GetBlocksArgs) : async Rechain.GetBlocksResult {
        return chain.icrc3_get_blocks(args);
    };

    public query func icrc3_get_archives(args : Rechain.GetArchivesArgs) : async Rechain.GetArchivesResult {
        return chain.icrc3_get_archives(args);
    };

    public query func icrc3_supported_block_types() : async [Rechain.BlockType] {
        return chain.icrc3_supported_block_types();
    };
    public query func icrc3_get_tip_certificate() : async ?Rechain.DataCertificate {
        return chain.icrc3_get_tip_certificate();
    };

    // ---------- Debug functions -----------

    // public func add_supported_ledger(id : Principal, ltype : { #icp; #icrc }) : () {
    //     dvf.add_ledger<system>(id, ltype);
    // };

    public query func get_ledger_errors() : async [[Text]] {
        dvf.getErrors();
    };

    public query func get_ledgers_info() : async [DeVeFi.LedgerInfo] {
        dvf.getLedgersInfo();
    };

};
