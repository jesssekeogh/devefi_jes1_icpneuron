import Map "mo:map/Map";
import MU "mo:mosup";

module {

    public type Mem = {
        main : Map.Map<Nat32, NodeMem>;
    };

    public func new() : MU.MemShell<Mem> = MU.new<Mem>({
        main = Map.new<Nat32, NodeMem>();
    });

    public type NodeMem = {
        variables : {
            var update_delay : UpdateDelay;
            var update_followee : UpdateFollowee;
            var update_dissolving : UpdateDissolving;
        };
        internals : {
            var updating : Updating;
            var local_idx : Nat32;
            var refresh_idx : ?Nat64;
            var spawning_neurons : [NeuronCache];
            var activity_log : [Activity];
        };
        cache : NeuronCache;
    };

    public type UpdateDelay = { #Default; #DelaySeconds : Nat64 };
    public type UpdateFollowee = { #Default; #FolloweeId : Nat64 };
    public type UpdateDissolving = { #StartDissolving; #KeepLocked };
    public type Updating = { #Init; #Calling : Nat64; #Done : Nat64 };
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
    };

};
