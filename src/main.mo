import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Option "mo:base/Option";
import Random "mo:base/Random";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import T "./types";
import DeVeFi "mo:devefi";
import ICRC55 "mo:devefi/ICRC55";
import Node "mo:devefi/node";
import IcpGovernanceInterface "mo:neuro/interfaces/nns_interface";
import Tools "mo:neuro/tools";
import AccountIdentifier "mo:account-identifier";
import Hex "mo:encoding/Hex";

shared ({ caller = owner }) actor class VectorStaking() = this {

    // Staking Vector Component
    // Stake neurons in vector nodes

    /////////////////
    /// Constants ///
    /////////////////

    let MINIMUM_STAKE = 1_0000_0000;

    let IcpGovernance = actor ("rrkah-fqaaa-aaaaa-aaaaq-cai") : IcpGovernanceInterface.Self;

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
        settings = Node.DEFAULT_SETTINGS;
        toShared = T.toShared;
        sourceMap = T.sourceMap;
        destinationMap = T.destinationMap;
        createRequest2Mem = T.createRequest2Mem;
        modifyRequestMut = T.modifyRequestMut;
        meta = T.meta;
    });

    /////////////////////////
    /// Main DeVeFi logic ///
    /////////////////////////

    ignore Timer.recurringTimer<system>(
        #seconds(2),
        func() : async () {
            label vloop for ((vid, vec) in nodes.entries()) {

                if (not nodes.hasDestination(vec, 0)) continue vloop;

                let ?source = nodes.getSource(vec, 0) else continue vloop;

                let bal = source.balance();
                let ledger_fee = source.fee();

                // node needs the min bal so it can stake and not get deleted
                // we continue if there is not atleast this amount of icp here
                if (bal <= NODE_FEE) continue vloop;

                switch (vec.custom) {
                    case (#stake(nodeMem)) {
                        // check node has no neuron
                        // IDEA: a node can own many neurons
                        if (Option.isSome(nodeMem.states.neuronId)) continue vloop;

                        // async tasks:
                        if (not Option.isSome(nodeMem.states.nonce)) {
                            // generate a random nonce that fits into Nat64
                            let ?nonce = Random.Finite(await Random.blob()).range(64) else continue vloop;

                            nodeMem.states.nonce := ?Nat64.fromNat(nonce);
                        } else if (not Option.isSome(nodeMem.states.neuronSubaccount)) {
                            // neurons subaccounts contain random nonces so one canister can have many neurons
                            let ?nonce = nodeMem.states.nonce;
                            let newSubaccount : Blob = Tools.computeNeuronStakingSubaccountBytes(nodeMem.init.neuron_controller, nonce);

                            // send from source to neuron account
                            let stakeAmount : Nat = bal - NODE_FEE;
                            source.send(#external_account({ owner = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"); subaccount = ?newSubaccount }), stakeAmount);

                            nodeMem.states.neuronSubaccount := ?newSubaccount;
                        } else if (not Option.isSome(nodeMem.states.neuronId)) {
                            let ?nonce = nodeMem.states.nonce;

                            let { command } = await IcpGovernance.manage_neuron({
                                id = null;
                                neuron_id_or_subaccount = null;
                                command = ? #ClaimOrRefresh({
                                    by = ? #MemoAndController({
                                        controller = ?nodeMem.init.neuron_controller;
                                        memo = nonce;
                                    });
                                });
                            });

                            let ?commandList = command else continue vloop;
                            switch (commandList) {
                                case (#ClaimOrRefresh { refreshed_neuron_id }) {

                                    let ?{ id } = refreshed_neuron_id else continue vloop;
                                    // save the neuronId
                                    nodeMem.states.neuronId := ?id;
                                };
                                case _ {};
                            };
                        } else {
                            // all of the above is okay, we can send any new icp from the source to the neuron account
                            let ?neuronSub = nodeMem.states.neuronSubaccount;
                            let stakeAmount : Nat = bal - NODE_FEE;
                            source.send(#external_account({ owner = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"); subaccount = ?neuronSub }), stakeAmount);
                        };
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

    public query ({ caller }) func icrc55_get_controller_nodes() : async ICRC55.GetControllerNodes {
        nodes.icrc55_get_controller_nodes(caller);
    };

    public shared ({ caller }) func icrc55_set_controller_nodes(vid : ICRC55.LocalNodeId) : async ICRC55.DeleteNodeResp {
        nodes.icrc55_delete_node(caller, vid);
    };

    public shared ({ caller }) func icrc55_delete_node(vid : ICRC55.LocalNodeId) : async ICRC55.DeleteNodeResp {
        nodes.icrc55_delete_node(caller, vid);
    };

    public shared ({ caller }) func icrc55_modify_node(vid : ICRC55.LocalNodeId, req : ICRC55.NodeModifyRequest, creq : T.ModifyRequest) : async ICRC55.NodeModifyResponse {
        nodes.icrc55_modify_node(caller, vid, req, creq);
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
