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

    public type OperationState<T> = {
        #Init;
        #Calling : Nat64; // Timestamp, retry after period
        #Done : T; // The result of the operation
    };

    public type NeuronId = { neuron_id : Nat64 };

    public type Timestamp = { timestamp : Nat64 };

    public type Delay = { delay_timestamp : Nat64 };

    public type Maturity = { maturity_e8s : Nat64 };

    public type TopicAndFollowee = (Int32, Nat64);

    public type Mem = {
        init : {
            ledger : Principal;
        };
        variables : {
            var delay_timestamp_seconds : ?Nat64;
            var followee : ?Nat64;
            var start_dissolve : ?Bool;
        };
        internals : {
            var claim_neuron : OperationState<NeuronId>;
            var update_delay : OperationState<Delay>;
            var start_dissolve : OperationState<Timestamp>;
            var disburse_neuron : OperationState<NeuronId>;
            var update_followees : OperationState<NeuronId>;
            var spawn_maturity : OperationState<Maturity>;
            var claim_maturity : OperationState<Timestamp>;
        };
        cache : {
            var followees : [TopicAndFollowee];
            var spawning_neurons : [NeuronId];
        };
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
        };
        variables : {
            delay_timestamp_seconds : ?Nat64;
            followee : ?Nat64;
            start_dissolve : ?Bool;
        };
    };

    public func createRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            variables = {
                var delay_timestamp_seconds = t.variables.delay_timestamp_seconds;
                var followee = t.variables.followee;
                var start_dissolve = t.variables.start_dissolve;
            };
            internals = {
                var claim_neuron = #Init;
                var update_delay = #Init;
                var start_dissolve = #Init;
                var disburse_neuron = #Init;
                var update_followees = #Init;
                var spawn_maturity = #Init;
                var claim_maturity = #Init;
            };
            cache = {
                var followees = [];
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
                start_dissolve = null;
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
            delay_timestamp_seconds : ?Nat64;
            followee : ?Nat64;
            start_dissolve : ?Bool;
        };
        internals : {
            claim_neuron : OperationState<NeuronId>;
            update_delay : OperationState<Delay>;
            start_dissolve : OperationState<Timestamp>;
            disburse_neuron : OperationState<NeuronId>;
            update_followees : OperationState<NeuronId>;
            spawn_maturity : OperationState<Maturity>;
            claim_maturity : OperationState<Timestamp>;
        };
        cache : {
            followees : [TopicAndFollowee];
            spawning_neurons : [NeuronId];
        };
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            variables = {
                delay_timestamp_seconds = t.variables.delay_timestamp_seconds;
                followee = t.variables.followee;
                start_dissolve = t.variables.start_dissolve;
            };
            internals = {
                claim_neuron = t.internals.claim_neuron;
                update_delay = t.internals.update_delay;
                start_dissolve = t.internals.start_dissolve;
                disburse_neuron = t.internals.disburse_neuron;
                update_followees = t.internals.update_followees;
                spawn_maturity = t.internals.spawn_maturity;
                claim_maturity = t.internals.claim_maturity;
            };
            cache = {
                followees = t.cache.followees;
                spawning_neurons = t.cache.spawning_neurons;
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
