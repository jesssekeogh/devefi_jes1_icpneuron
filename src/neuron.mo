import Result "mo:base/Result";
import Node "mo:devefi/node";
import ICRC55 "mo:devefi/ICRC55";
import U "mo:devefi/utils";
import Debug "mo:base/Debug";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import GovT "mo:neuro/interfaces/nns_interface";

module {

    public func meta(all_ledgers : [ICRC55.SupportedLedger]) : ICRC55.NodeMeta {
        {
            id = "nns_neuron"; // This has to be same as the variant in vec.custom
            name = "NNS Neuron";
            description = "Stake NNS neurons and receive ICP maturity";
            supported_ledgers = all_ledgers;
            version = #alpha;
            billing = billing();
        };
    };

    public func billing() : ICRC55.Billing {
        {
            ledger = Principal.fromText("7tjcv-pp777-77776-qaaaa-cai"); // TODO change, using Test ledger now
            // ledger = Principal.fromText("f54if-eqaaa-aaaaq-aacea-cai");
            min_create_balance = 5000000;
            cost_per_day = 10_0000;
            operation_cost = 1000;
            freezing_threshold_days = 10;
            exempt_daily_cost_balance = null;
            transaction_fee = #none;
            split = {
                pylon = 300;
                author = 500;
                affiliate = 200;
            };
        };
    };

    public func authorAccount() : ICRC55.Account {
        {
            owner = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"); // TODO change
            subaccount = null;
        };
    };

    public type Updating = { #Init; #Calling : Nat64; #Done : Nat64 };

    public type SpawningNeuronCache = {
        var nonce : Nat64;
        var maturity_e8s_equivalent : Nat64;
        var cached_neuron_stake_e8s : Nat64;
        var created_timestamp_seconds : Nat64;
    };

    public type SharedSpawningNeuronCache = {
        nonce : Nat64;
        maturity_e8s_equivalent : Nat64;
        cached_neuron_stake_e8s : Nat64;
        created_timestamp_seconds : Nat64;
    };

    public type NeuronCache = {
        var neuron_id : ?Nat64;
        var nonce : ?Nat64;
        var maturity_e8s_equivalent : ?Nat64;
        var cached_neuron_stake_e8s : ?Nat64;
        var created_timestamp_seconds : ?Nat64;
        var followees : [(Int32, GovT.Followees)];
        var dissolve_delay_seconds : ?Nat64;
        var state : ?Int32;
        var voting_power : ?Nat64;
        var age_seconds : ?Nat64;
    };

    public type SharedNeuronCache = {
        neuron_id : ?Nat64;
        nonce : ?Nat64;
        maturity_e8s_equivalent : ?Nat64;
        cached_neuron_stake_e8s : ?Nat64;
        created_timestamp_seconds : ?Nat64;
        followees : [(Int32, GovT.Followees)];
        dissolve_delay_seconds : ?Nat64;
        state : ?Int32;
        voting_power : ?Nat64;
        age_seconds : ?Nat64;
    };

    public type Mem = {
        init : {
            ledger : Principal;
            delay_seconds : Nat64;
        };
        variables : {
            var update_followee : Nat64;
            var update_dissolving : Bool;
        };
        internals : {
            var updating : Updating;
            var local_idx : Nat32;
            var refresh_idx : ?Nat64;
            var spawning_neurons : [SpawningNeuronCache];
        };
        cache : NeuronCache;
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
            delay_seconds : Nat64;
        };
        variables : {
            update_followee : Nat64;
            update_dissolving : Bool;
        };
    };

    public func createRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            variables = {
                var update_followee = t.variables.update_followee;
                var update_dissolving = t.variables.update_dissolving;
            };
            internals = {
                var updating = #Init;
                var local_idx = 0;
                var refresh_idx = null;
                var spawning_neurons = [];
            };
            cache = {
                var neuron_id = null;
                var nonce = null;
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
                delay_seconds = 15897600; // 184 days
            };
            variables = {
                update_followee = 8571487073262291504; // neuronpool known neuron
                update_dissolving = false; // not dissolving
            };
        };
    };

    public type ModifyRequest = {
        update_followee : ?Nat64;
        update_dissolving : ?Bool;
    };

    public func modifyRequestMut(mem : Mem, t : ModifyRequest) : Result.Result<(), Text> {
        mem.variables.update_followee := Option.get(t.update_followee, mem.variables.update_followee);
        mem.variables.update_dissolving := Option.get(t.update_dissolving, mem.variables.update_dissolving);
        #ok();
    };

    public type Shared = {
        init : {
            ledger : Principal;
            delay_seconds : Nat64;
        };
        variables : {
            update_followee : Nat64;
            update_dissolving : Bool;
        };
        internals : {
            updating : Updating;
            local_idx : Nat32;
            refresh_idx : ?Nat64;
            spawning_neurons : [SharedSpawningNeuronCache];
        };
        cache : SharedNeuronCache;
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            variables = {
                update_followee = t.variables.update_followee;
                update_dissolving = t.variables.update_dissolving;
            };
            internals = {
                updating = t.internals.updating;
                local_idx = t.internals.local_idx;
                refresh_idx = t.internals.refresh_idx;
                spawning_neurons = Array.map(
                    t.internals.spawning_neurons,
                    func(neuron : SpawningNeuronCache) : SharedSpawningNeuronCache {

                        {
                            nonce = neuron.nonce;
                            maturity_e8s_equivalent = neuron.maturity_e8s_equivalent;
                            cached_neuron_stake_e8s = neuron.cached_neuron_stake_e8s;
                            created_timestamp_seconds = neuron.created_timestamp_seconds;
                        };
                    },
                );
            };
            cache = {
                neuron_id = t.cache.neuron_id;
                nonce = t.cache.nonce;
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

    public func request2Sources(t : Mem, id : Node.NodeId, thiscan : Principal, sources : [ICRC55.Endpoint]) : Result.Result<[ICRC55.Endpoint], Text> {
        let #ok(a0) = U.expectSourceAccount(t.init.ledger, thiscan, sources, 0) else return #err("Invalid source 0");
        let sourceName : Text = switch (sources.size()) {
            case (0) { "" };
            case _ {
                let #ic({ name }) = sources[0] else {
                    return #err("Source name not found");
                };
                name;
            };
        };

        #ok(
            Array.tabulate<ICRC55.Endpoint>(
                1,
                func(idx : Nat) = #ic {
                    ledger = t.init.ledger;
                    account = Option.get(
                        a0,
                        {
                            owner = thiscan;
                            subaccount = ?Node.port2subaccount({
                                vid = id;
                                flow = #input;
                                id = Nat8.fromNat(idx);
                            });
                        },
                    );
                    name = sourceName;
                },
            )
        );
    };

    public func request2Destinations(t : Mem, req : [ICRC55.DestinationEndpoint]) : Result.Result<[ICRC55.DestinationEndpoint], Text> {
        let #ok(acc) = U.expectDestinationAccount(t.init.ledger, req, 0) else return #err("Invalid destination 0");
        let destinationName : Text = switch (req.size()) {
            case (0) { "" };
            case _ {
                let #ic({ name }) = req[0] else {
                    return #err("Destination name not found");
                };
                name;
            };
        };

        return #ok([
            #ic {
                ledger = t.init.ledger;
                account = acc;
                name = destinationName;
            }
        ]);
    };

};
