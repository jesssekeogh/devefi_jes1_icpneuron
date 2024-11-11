import Principal "mo:base/Principal";
import Ledgers "mo:devefi/ledgers";
import ICRC55 "mo:devefi/ICRC55";
import Rechain "mo:rechain";
import RT "./rechain";
import Timer "mo:base/Timer";
import U "mo:devefi/utils";
import T "./vector_modules";
import MU_sys "mo:devefi/sys";

import IcpNeuronVector "../../src";
import Core "mo:devefi/core";

shared ({ caller = owner }) actor class NNSVECTOR() = this {

    let me_can = Principal.fromActor(this);
    stable let chain_mem = Rechain.Mem.Rechain.V1.new();

    var chain = Rechain.Chain<system, RT.DispatchAction, RT.DispatchActionError>({
        settings = ?{
            Rechain.DEFAULT_SETTINGS with supportedBlocks = [{
                block_type = "55vec";
                url = "https://github.com/dfinity/ICRC/issues/55";
            }];
        };
        xmem = chain_mem;
        encodeBlock = RT.encodeBlock;
        reducers = [];
        me_can;
    });

    stable let dvf_mem_1 = Ledgers.Mem.Ledgers.V1.new();

    let dvf = Ledgers.Ledgers<system>({ xmem = dvf_mem_1; me_can });

    stable let mem_core_1 = Core.Mem.Core.V1.new();

    let test_icrc : Principal = Principal.fromText("7tjcv-pp777-77776-qaaaa-cai");
    let icp_ledger = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");

    dvf.add_ledger<system>(test_icrc, #icrc);
    dvf.add_ledger<system>(icp_ledger, #icp);

    let billing : ICRC55.BillingPylon = {
        ledger = test_icrc;
        min_create_balance = 3000000;
        operation_cost = 1000;
        freezing_threshold_days = 10;
        exempt_daily_cost_balance = null;
        split = {
            platform = 20;
            pylon = 20;
            author = 40;
            affiliate = 20;
        };
        pylon_account = {
            owner = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
            subaccount = null;
        };
        platform_account = {
            owner = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
            subaccount = null;
        };
    };

    let core = Core.Mod<system>({
        xmem = mem_core_1;
        settings = {
            BILLING = billing;
            PYLON_NAME = "NNS Vector";
            PYLON_GOVERNED_BY = "Neutrinite DAO";
            TEMP_NODE_EXPIRATION_SEC = 3600;
            MAX_INSTRUCTIONS_PER_HEARTBEAT = 300_000_000;
            REQUEST_MAX_EXPIRE_SEC = 3600;
            ALLOW_TEMP_NODE_CREATION = true;
        };
        dvf;
        chain;
        me_can;
    });

    // Components
    let mem_vec_icpneuron_1 = IcpNeuronVector.Mem.Vector.V1.new();
    let devefi_jes1_icpneuron = IcpNeuronVector.Mod({ xmem = mem_vec_icpneuron_1; core; dvf });

    let vmod = T.VectorModules({ devefi_jes1_icpneuron });

    let sys = MU_sys.Mod<system, T.CreateRequest, T.Shared, T.ModifyRequest>({
        xmem = mem_core_1;
        dvf;
        core;
        vmod;
        me_can;
    });

    private func proc() { devefi_jes1_icpneuron.run() };

    private func async_proc() : async* () { await* devefi_jes1_icpneuron.runAsync() };

    ignore Timer.recurringTimer<system>(
        #seconds 2,
        func() : async () { core.heartbeat(proc) },
    );

    ignore Timer.recurringTimer<system>(
        #seconds 2,
        func() : async () { await* async_proc() },
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

    public query func get_ledger_errors() : async [[Text]] {
        dvf.getErrors();
    };

    public query func get_ledgers_info() : async [Ledgers.LedgerInfo] {
        dvf.getLedgersInfo();
    };

};
