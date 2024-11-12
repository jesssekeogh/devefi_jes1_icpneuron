import GovT "mo:neuro/interfaces/nns_interface";

module {

    public type CreateRequest = {
        variables : {
            update_delay : UpdateDelay;
            update_followee : UpdateFollowee;
            update_dissolving : UpdateDissolving;
        };
    };

    public type ModifyRequest = {
        update_delay : ?UpdateDelay;
        update_followee : ?UpdateFollowee;
        update_dissolving : ?UpdateDissolving;
    };

    public type Shared = {
        variables : {
            update_delay : UpdateDelay;
            update_followee : UpdateFollowee;
            update_dissolving : UpdateDissolving;
        };
        internals : {
            updating : Updating;
            local_idx : Nat32;
            refresh_idx : ?Nat64;
            spawning_neurons : [SharedNeuronCache];
            activity_log : [Activity];
        };
        cache : SharedNeuronCache;
    };

    public type UpdateDelay = { #Default; #DelaySeconds : Nat64 };
    public type UpdateFollowee = { #Default; #FolloweeId : Nat64 };
    public type UpdateDissolving = { #StartDissolving; #KeepLocked };
    public type Updating = { #Init; #Calling : Nat64; #Done : Nat64 };
    public type Activity = {
        #Ok : { operation : Text; timestamp : Nat64 };
        #Err : { operation : Text; msg : Text; timestamp : Nat64 };
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

}