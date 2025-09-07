import Map "mo:map/Map";
import MU "mo:mosup";
import Ver3 "./v3";

module {

    public type Mem = {
        main : Map.Map<Nat32, NodeMem>;
    };

    public func new() : MU.MemShell<Mem> = MU.new<Mem>({
        main = Map.new<Nat32, NodeMem>();
    });

    public func upgrade(from : MU.MemShell<Ver3.Mem>) : MU.MemShell<Mem> {
        MU.upgrade(
            from,
            func(t : Ver3.Mem) : Mem {
                {
                    main = Map.map(
                        t.main,
                        Map.n32hash,
                        func(_nodeId : Nat32, nodeMem : Ver3.NodeMem) : NodeMem {
                            {
                                variables = {
                                    var dissolve_delay = nodeMem.variables.dissolve_delay;
                                    var dissolve_status = nodeMem.variables.dissolve_status;
                                    var followee = nodeMem.variables.followee;
                                    var hotkey = #None;
                                    var visibility = #Private;
                                };
                                internals = {
                                    var updating = nodeMem.internals.updating;
                                    var local_idx = nodeMem.internals.local_idx;
                                    var refresh_idx = nodeMem.internals.refresh_idx;
                                    var neuron_claimed = true;
                                    var spawning_neurons = [];
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
                                    var voting_power_refreshed_timestamp_seconds = nodeMem.cache.voting_power_refreshed_timestamp_seconds;
                                    var potential_voting_power = nodeMem.cache.potential_voting_power;
                                    var deciding_voting_power = nodeMem.cache.deciding_voting_power;
                                    var maturity_disbursements_in_progress = nodeMem.cache.maturity_disbursements_in_progress;
                                    var hot_keys = [];
                                    var visibility = null;
                                };
                                var neuron_cache = [];
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
            var hotkey : Hotkey;
            var visibility : Visibility;
        };
        internals : {
            var updating : UpdatingStatus;
            var local_idx : Nat32;
            var refresh_idx : ?Nat64;
            var neuron_claimed : Bool;
            var spawning_neurons : [NeuronCache];
        };
        cache : NeuronCache;
        var neuron_cache : [SharedNeuronCache];
        var log : [Activity];
    };

    public type Visibility = {
        #Private;
        #Public;
    };

    public type Hotkey = {
        #None;
        #HotkeyId : Principal;
    };

    public type DissolveDelay = {
        #Default;
        #DelayDays : Nat64;
    };

    public type Followee = {
        #None;
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
        var maturity_disbursements_in_progress : ?[{
            account_identifier_to_disburse_to : ?{ hash : Blob };
            timestamp_of_disbursement_seconds : ?Nat64;
            amount_e8s : ?Nat64;
            account_to_disburse_to : ?{ owner : ?Principal; subaccount : ?Blob };
            finalize_disbursement_timestamp_seconds : ?Nat64;
        }];
        var hot_keys : [Principal];
        var visibility : ?Int32;
    };

    public type SharedNeuronCache = {
        neuron_id : ?Nat64;
        nonce : ?Nat64;
        maturity_e8s_equivalent : ?Nat64;
        cached_neuron_stake_e8s : ?Nat64;
        created_timestamp_seconds : ?Nat64;
        followees : [(Int32, { followees : [{ id : Nat64 }] })];
        dissolve_delay_seconds : ?Nat64;
        state : ?Int32;
        voting_power : ?Nat64;
        age_seconds : ?Nat64;
        voting_power_refreshed_timestamp_seconds : ?Nat64;
        potential_voting_power : ?Nat64;
        deciding_voting_power : ?Nat64;
        maturity_disbursements_in_progress : ?[{
            account_identifier_to_disburse_to : ?{ hash : Blob };
            timestamp_of_disbursement_seconds : ?Nat64;
            amount_e8s : ?Nat64;
            account_to_disburse_to : ?{ owner : ?Principal; subaccount : ?Blob };
            finalize_disbursement_timestamp_seconds : ?Nat64;
        }];
        hot_keys : [Principal];
        visibility : ?Int32;
    };

};
