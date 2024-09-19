import Result "mo:base/Result";
import Node "mo:devefi/node";
import ICRC55 "mo:devefi/ICRC55";
import U "mo:devefi/utils";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

module {

    public func meta(all_ledgers : [ICRC55.SupportedLedger]) : ICRC55.NodeMeta {
        {
            id = "nns_neuron"; // This has to be same as the variant in vec.custom
            name = "NNS Neuron";
            description = "Stake NNS neurons and receive ICP maturity";
            governed_by = "Neutrinite DAO";
            supported_ledgers = all_ledgers;
            pricing = "0.0001 ICP"; // TODO change to NTN
            version = #alpha;
        };
    };

    public type NeuronId = Nat64;

    public type Timestamp = Nat64;

    public type Hotkey = Principal;

    public type TopicFollowee = { topic : Int32; followee : Nat64 };

    public type OperationState<T> = {
        #Init;
        #Calling : Nat64; // Timestamp, retry after period
        #Done : T; // The result of the operation
    };

    public type Mem = {
        init : {
            ledger : Principal;
        };
        variables : {
            var delay_timestamp_seconds : ?Timestamp;
            var followee : ?NeuronId;
            var hotkey : ?Hotkey;
            var start_dissolve : ?Bool;
            var disburse_neuron : ?Bool;
        };
        internal_lifecycle : {
            var claim_neuron : OperationState<NeuronId>;
            var update_delay : OperationState<Timestamp>;
            var start_dissolve : OperationState<Timestamp>;
            var disburse_neuron : OperationState<Timestamp>;
        };
        internal_followees : {
            var update_followees : OperationState<NeuronId>;
            var cached_followees : [TopicFollowee];
        };
        internal_hotkey : {
            var update_hotkey : OperationState<Hotkey>;
            var cached_hotkey : ?Hotkey;
        };
        internal_maturity : {
            var spawn_maturity : OperationState<Timestamp>;
            var claim_maturity : OperationState<Timestamp>;
            var spawning_neurons : [NeuronId];
        };
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
        };
        variables : {
            delay_timestamp_seconds : ?Timestamp;
            followee : ?NeuronId;
            hotkey : ?Hotkey;
            start_dissolve : ?Bool;
            disburse_neuron : ?Bool;
        };
    };

    public func createRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            variables = {
                var delay_timestamp_seconds = t.variables.delay_timestamp_seconds;
                var followee = t.variables.followee;
                var hotkey = t.variables.hotkey;
                var start_dissolve = t.variables.start_dissolve;
                var disburse_neuron = t.variables.disburse_neuron;
            };
            internal_lifecycle = {
                var claim_neuron = #Init;
                var update_delay = #Init;
                var start_dissolve = #Init;
                var disburse_neuron = #Init;
            };
            internal_followees = {
                var update_followees = #Init;
                var cached_followees = [];
            };
            internal_hotkey = {
                var update_hotkey = #Init;
                var cached_hotkey = null;
            };
            internal_maturity = {
                var spawn_maturity = #Init;
                var claim_maturity = #Init;
                var spawning_neurons = [];
            };
        };
    };

    public func defaults(all_ledgers : [ICRC55.SupportedLedger]) : CreateRequest {
        let #ic(ledger) = all_ledgers[0] else Debug.trap("No ledgers found");
        {
            init = {
                ledger = ledger;
            };
            variables = {
                delay_timestamp_seconds = null;
                followee = null;
                hotkey = null;
                start_dissolve = null;
                disburse_neuron = null;
            };
        };
    };

    public type ModifyRequest = {

    };

    public func modifyRequestMut(mem : Mem, t : ModifyRequest) : Result.Result<(), Text> {
        // when variable changes set the associating internal back to init
        #ok();
    };

    public type Shared = {
        init : {
            ledger : Principal;
        };
        variables : {
            delay_timestamp_seconds : ?Timestamp;
            followee : ?NeuronId;
            hotkey : ?Hotkey;
            start_dissolve : ?Bool;
            disburse_neuron : ?Bool;
        };
        internal_lifecycle : {
            claim_neuron : OperationState<NeuronId>;
            update_delay : OperationState<Timestamp>;
            start_dissolve : OperationState<Timestamp>;
            disburse_neuron : OperationState<Timestamp>;
        };
        internal_followees : {
            update_followees : OperationState<NeuronId>;
            cached_followees : [TopicFollowee];
        };
        internal_hotkey : {
            update_hotkey : OperationState<Hotkey>;
            cached_hotkey : ?Hotkey;
        };
        internal_maturity : {
            spawn_maturity : OperationState<Timestamp>;
            claim_maturity : OperationState<Timestamp>;
            spawning_neurons : [NeuronId];
        };
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            variables = {
                delay_timestamp_seconds = t.variables.delay_timestamp_seconds;
                followee = t.variables.followee;
                hotkey = t.variables.hotkey;
                start_dissolve = t.variables.start_dissolve;
                disburse_neuron = t.variables.disburse_neuron;
            };
            internal_lifecycle = {
                claim_neuron = t.internal_lifecycle.claim_neuron;
                update_delay = t.internal_lifecycle.update_delay;
                start_dissolve = t.internal_lifecycle.start_dissolve;
                disburse_neuron = t.internal_lifecycle.disburse_neuron;
            };
            internal_followees = {
                update_followees = t.internal_followees.update_followees;
                cached_followees = t.internal_followees.cached_followees;
            };
            internal_hotkey = {
                update_hotkey = t.internal_hotkey.update_hotkey;
                cached_hotkey = t.internal_hotkey.cached_hotkey;
            };
            internal_maturity = {
                spawn_maturity = t.internal_maturity.spawn_maturity;
                claim_maturity = t.internal_maturity.claim_maturity;
                spawning_neurons = t.internal_maturity.spawning_neurons;
            };
        };
    };

    // Mapping of source node ports
    public func request2Sources(t : Mem, id : Node.NodeId, thiscan : Principal) : Result.Result<[ICRC55.Endpoint], Text> {
        #ok(
            Array.tabulate<ICRC55.Endpoint>(
                1,
                func(idx : Nat) = #ic {
                    ledger = t.init.ledger;
                    account = {
                        owner = thiscan;
                        subaccount = ?Node.port2subaccount({
                            vid = id;
                            flow = #input;
                            id = Nat8.fromNat(idx);
                        });
                    };
                    name = "";
                },
            )
        );
    };

    // Mapping of destination node ports
    //
    // Allows you to change destinations and dynamically create new ones based on node state upon creation or modification
    // Fills in the account field when destination accounts are given
    // or leaves them null when not given
    public func request2Destinations(t : Mem, req : [ICRC55.DestinationEndpoint]) : Result.Result<[ICRC55.DestinationEndpoint], Text> {
        let #ok(acc) = U.expectAccount(t.init.ledger, req, 0) else return #err("Invalid destination 0");

        #ok([
            #ic {
                ledger = t.init.ledger;
                account = acc;
                name = "";
            }
        ]);
    };

};
