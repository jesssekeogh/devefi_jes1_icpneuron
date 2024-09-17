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

    public type Mem = {
        init : {
            ledger : Principal;
        };
        variables : {
            var dissolve_timestamp_seconds : ?Nat64;
            var followee : ?Nat64;
            var hotkey : ?Principal;
            var hotkey_to_remove : ?Principal;
        };
        internals : {
            var generate_nonce : OperationState<Nat64>; // nonce
            var claim_neuron : OperationState<Nat64>; // neuronId
            var update_followee : OperationState<Nat64>; // neuronId
            var update_delay : OperationState<Nat64>; // dissolve delay seconds
            var add_hotkey : OperationState<Principal>; // node controller
            var remove_hotkey : OperationState<Principal>; // last hotkey removed
            maturity_operations : {
                var spawn_maturity : OperationState<Nat64>; // timestamp
                var claim_maturity : OperationState<Nat64>; // timestamp
                var spawning_neurons : [Nat64];
            };
        };
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
        };
        variables : {
            dissolve_timestamp_seconds : ?Nat64; // if this gets changed, we update to the new delay
            followee : ?Nat64; // same as above. This will be set for all topics
            hotkey : ?Principal;
            hotkey_to_remove : ?Principal;
        };
    };

    public func createRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            variables = {
                var dissolve_timestamp_seconds = t.variables.dissolve_timestamp_seconds;
                var followee = t.variables.followee;
                var hotkey = t.variables.hotkey;
                var hotkey_to_remove = t.variables.hotkey_to_remove;
            };
            internals = {
                var generate_nonce = #Init;
                var claim_neuron = #Init;
                var update_followee = #Init;
                var update_delay = #Init;
                var add_hotkey = #Init;
                var remove_hotkey = #Init;
                maturity_operations = {
                    var spawn_maturity = #Init;
                    var claim_maturity = #Init;
                    var spawning_neurons = [];
                };
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
                dissolve_timestamp_seconds = null;
                followee = null;
                hotkey = null;
                hotkey_to_remove = null;
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
            dissolve_timestamp_seconds : ?Nat64;
            followee : ?Nat64;
            hotkey : ?Principal;
            hotkey_to_remove : ?Principal;
        };
        internals : {
            generate_nonce : OperationState<Nat64>;
            claim_neuron : OperationState<Nat64>;
            update_followee : OperationState<Nat64>;
            update_delay : OperationState<Nat64>;
            add_hotkey : OperationState<Principal>;
            remove_hotkey : OperationState<Principal>;
            maturity_operations : {
                spawn_maturity : OperationState<Nat64>; // timestamp
                claim_maturity : OperationState<Nat64>; // timestamp
                spawning_neurons : [Nat64];
            };
        };
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            variables = {
                dissolve_timestamp_seconds = t.variables.dissolve_timestamp_seconds;
                followee = t.variables.followee;
                hotkey = t.variables.hotkey;
                hotkey_to_remove = t.variables.hotkey_to_remove;
            };
            internals = {
                generate_nonce = t.internals.generate_nonce;
                claim_neuron = t.internals.claim_neuron;
                update_followee = t.internals.update_followee;
                update_delay = t.internals.update_delay;
                add_hotkey = t.internals.add_hotkey;
                remove_hotkey = t.internals.remove_hotkey;
                maturity_operations = {
                    spawn_maturity = t.internals.maturity_operations.spawn_maturity;
                    claim_maturity = t.internals.maturity_operations.claim_maturity;
                    spawning_neurons = t.internals.maturity_operations.spawning_neurons;
                };
            };
        };
    };

    // Mapping of source node ports
    public func request2Sources(t : Mem, id : Node.NodeId, thiscan : Principal) : Result.Result<[ICRC55.Endpoint], Text> {
        #ok(
            Array.tabulate<ICRC55.Endpoint>(1, func(idx:Nat) = #ic {
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
            })
        );
    };

    // Mapping of destination node ports
    //
    // Allows you to change destinations and dynamically create new ones based on node state upon creation or modification
    // Fills in the account field when destination accounts are given
    // or leaves them null when not given
    public func request2Destinations(t : Mem, req:[ICRC55.DestinationEndpoint]) : Result.Result<[ICRC55.DestinationEndpoint], Text> {
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
