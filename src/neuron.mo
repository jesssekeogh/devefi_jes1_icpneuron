import Result "mo:base/Result";
import Node "mo:devefi/node";
import ICRC55 "mo:devefi/ICRC55";
import U "mo:devefi/utils";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import NT "mo:neuro/types";

module {

    public func meta(all_ledgers : [ICRC55.SupportedLedger]) : ICRC55.NodeMeta {
        {
            id = "nns_neuron"; // This has to be same as the variant in vec.custom
            name = "NNS Neuron";
            description = "Stake NNS neurons and receive ICP maturity";
            governed_by = "Neutrinite DAO";
            supported_ledgers = all_ledgers;
            pricing = "1 NTN";
            version = #alpha;
        };
    };

    public type Mem = {
        init : {
            ledger : Principal;
        };
        variables : {
            var update_followee : ?NT.NnsNeuronId;
            var update_dissolving : ?Bool;
            var update_delay_seconds : ?Nat32; // can update to higher amount, just do this amount - cache amount = new amount
        };
        internals : {
            var updating : { #Idle; #Calling : Nat64 }; // use try finally on every func and call the configs
        };
        cache : {
            var neuron_id : ?NT.NnsNeuronId;
            var spawning_neurons : [NT.NnsNeuronId];
            var maturity_e8s_equivalent : ?Nat64;
            var cached_neuron_stake_e8s : ?Nat64;
            var created_timestamp_seconds : ?Nat64;
            var followees : [(Int32, { followees : [{ id : NT.NnsNeuronId }] })];
            var dissolve_delay_seconds : ?Nat64;
            var state : ?Int32;
            var voting_power : ?Nat64;
            var age_seconds : ?Nat64;
        };
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
        };
        variables : {
            update_followee : ?NT.NnsNeuronId;
            update_dissolving : ?Bool;
            update_delay_seconds : ?Nat32;
        };
    };

    public func createRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            variables = {
                var update_followee = t.variables.update_followee;
                var update_dissolving = t.variables.update_dissolving;
                var update_delay_seconds = t.variables.update_delay_seconds;
            };
            internals = {
                var updating = #Idle;
            };
            cache = {
                var neuron_id = null;
                var spawning_neurons = [];
                var maturity_e8s_equivalent = null;
                var cached_neuron_stake_e8s = null;
                var created_timestamp_seconds = null;
                var followees = [];
                var dissolve_delay_seconds = null;
                var state = null;
                var voting_power = null;
                var age_seconds = null;
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
                update_followee = null;
                update_dissolving = null;
                update_delay_seconds = null;
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
            update_followee : ?NT.NnsNeuronId;
            update_dissolving : ?Bool;
            update_delay_seconds : ?Nat32;
        };
        internals : {
            updating : { #Idle; #Calling : Nat64 };
        };
        cache : {
            neuron_id : ?NT.NnsNeuronId;
            spawning_neurons : [NT.NnsNeuronId];
            maturity_e8s_equivalent : ?Nat64;
            cached_neuron_stake_e8s : ?Nat64;
            created_timestamp_seconds : ?Nat64;
            followees : [(Int32, { followees : [{ id : NT.NnsNeuronId }] })];
            dissolve_delay_seconds : ?Nat64;
            state : ?Int32;
            voting_power : ?Nat64;
            age_seconds : ?Nat64;
        };
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            variables = {
                update_followee = t.variables.update_followee;
                update_dissolving = t.variables.update_dissolving;
                update_delay_seconds = t.variables.update_delay_seconds;
            };
            internals = {
                updating = t.internals.updating;
            };
            cache = {
                neuron_id = t.cache.neuron_id;
                spawning_neurons = t.cache.spawning_neurons;
                maturity_e8s_equivalent = t.cache.maturity_e8s_equivalent;
                cached_neuron_stake_e8s = t.cache.cached_neuron_stake_e8s;
                created_timestamp_seconds = t.cache.created_timestamp_seconds;
                followees = t.cache.followees;
                dissolve_delay_seconds = t.cache.dissolve_delay_seconds;
                state = t.cache.state;
                voting_power = t.cache.voting_power;
                age_seconds = t.cache.age_seconds;
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
