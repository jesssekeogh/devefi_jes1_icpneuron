import Ver1 "./memory/v1";
import GovT "mo:neuro/interfaces/nns_interface";

module {

    public type CreateRequest = {
        variables : {
            dissolve_delay : Ver1.DissolveDelay;
            dissolve_status : Ver1.DissolveStatus;
            followee : Ver1.Followee;
        };
    };

    public type ModifyRequest = {
        dissolve_delay : ?Ver1.DissolveDelay;
        dissolve_status : ?Ver1.DissolveStatus;
        followee : ?Ver1.Followee;
    };

    public type Shared = {
        variables : {
            dissolve_delay : Ver1.DissolveDelay;
            dissolve_status : Ver1.DissolveStatus;
            followee : Ver1.Followee;
        };
        internals : {
            updating : Ver1.UpdatingStatus;
            local_idx : Nat32;
            refresh_idx : ?Nat64;
            spawning_neurons : [SharedNeuronCache];
        };
        cache : SharedNeuronCache;
        log : [Ver1.Activity];
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
    };

    public type Neuron = GovT.Neuron;

    public type NeuronInfo = GovT.NeuronInfo;

};
