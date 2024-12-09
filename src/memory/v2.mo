import Map "mo:map/Map";
import MU "mo:mosup";
import Ver1 "./v1";
import Array "mo:base/Array";

module {

    public type Mem = {
        main : Map.Map<Nat32, NodeMem>;
    };

    public func new() : MU.MemShell<Mem> = MU.new<Mem>({
        main = Map.new<Nat32, NodeMem>();
    });

    public func upgrade(from : MU.MemShell<Ver1.Mem>) : MU.MemShell<Mem> {
        MU.upgrade(
            from,
            func(t : Ver1.Mem) : Mem {
                {
                    main = Map.map(
                        t.main,
                        Map.n32hash,
                        func(_nodeId : Nat32, nodeMem : Ver1.NodeMem) : NodeMem {
                            {
                                variables = {
                                    var dissolve_delay = nodeMem.variables.dissolve_delay;
                                    var dissolve_status = nodeMem.variables.dissolve_status;
                                    var followee = nodeMem.variables.followee;
                                };
                                internals = {
                                    var updating = nodeMem.internals.updating;
                                    var local_idx = nodeMem.internals.local_idx;
                                    var refresh_idx = nodeMem.internals.refresh_idx;
                                    var spawning_neurons = Array.map(
                                        nodeMem.internals.spawning_neurons,
                                        func(neuron : Ver1.NeuronCache) : NeuronCache {
                                            {
                                                var neuron_id = neuron.neuron_id;
                                                var nonce = neuron.nonce;
                                                var maturity_e8s_equivalent = neuron.maturity_e8s_equivalent;
                                                var cached_neuron_stake_e8s = neuron.cached_neuron_stake_e8s;
                                                var created_timestamp_seconds = neuron.created_timestamp_seconds;
                                                var followees = neuron.followees;
                                                var dissolve_delay_seconds = neuron.dissolve_delay_seconds;
                                                var state = neuron.state;
                                                var voting_power = neuron.voting_power;
                                                var age_seconds = neuron.age_seconds;
                                                var voting_power_refreshed_timestamp_seconds = null;
                                                var potential_voting_power = null;
                                                var deciding_voting_power = null;
                                            };
                                        },
                                    );
                                };
                                cache = {
                                    var neuron_id = nodeMem.cache.neuron_id;
                                    var nonce = nodeMem.cache.nonce;
                                    var maturity_e8s_equivalent = nodeMem.cache.maturity_e8s_equivalent;
                                    var cached_neuron_stake_e8s = nodeMem.cache.cached_neuron_stake_e8s;
                                    var created_timestamp_seconds = nodeMem.cache.created_timestamp_seconds;
                                    var followees = nodeMem.cache.followees;
                                    var dissolve_delay_seconds = nodeMem.cache.dissolve_delay_seconds;
                                    var state = nodeMem.cache.state;
                                    var voting_power = nodeMem.cache.voting_power;
                                    var age_seconds = nodeMem.cache.age_seconds;
                                    var voting_power_refreshed_timestamp_seconds = null;
                                    var potential_voting_power = null;
                                    var deciding_voting_power = null;
                                };
                                var log = nodeMem.log;
                            };
                        },
                    );
                };
            },
        );
    };

    public type NodeMem = {
        variables : {
            var dissolve_delay : DissolveDelay;
            var dissolve_status : DissolveStatus;
            var followee : Followee;
        };
        internals : {
            var updating : UpdatingStatus;
            var local_idx : Nat32;
            var refresh_idx : ?Nat64;
            var spawning_neurons : [NeuronCache];
        };
        cache : NeuronCache;
        var log : [Activity];
    };

    public type DissolveDelay = {
        #Default;
        #DelayDays : Nat64;
    };

    public type Followee = {
        #Default;
        #FolloweeId : Nat64;
    };

    public type DissolveStatus = {
        #Dissolving;
        #Locked;
    };

    public type UpdatingStatus = {
        #Init;
        #Calling : Nat64;
        #Done : Nat64;
    };

    public type Activity = {
        #Ok : { operation : Text; timestamp : Nat64 };
        #Err : { operation : Text; msg : Text; timestamp : Nat64 };
    };

    public type NeuronCache = {
        var neuron_id : ?Nat64;
        var nonce : ?Nat64;
        var maturity_e8s_equivalent : ?Nat64;
        var cached_neuron_stake_e8s : ?Nat64;
        var created_timestamp_seconds : ?Nat64;
        var followees : [(Int32, { followees : [{ id : Nat64 }] })];
        var dissolve_delay_seconds : ?Nat64;
        var state : ?Int32;
        var voting_power : ?Nat64;
        var age_seconds : ?Nat64;
        var voting_power_refreshed_timestamp_seconds : ?Nat64;
        var potential_voting_power : ?Nat64;
        var deciding_voting_power : ?Nat64;
    };

};
