import Ver3 "./memory/v3";
import GovT "mo:neuro/interfaces/nns_interface";

module {

    public type CreateRequest = {
        variables : {
            dissolve_delay : Ver3.DissolveDelay;
            dissolve_status : Ver3.DissolveStatus;
            followee : Ver3.Followee;
        };
    };

    public type ModifyRequest = {
        dissolve_delay : ?Ver3.DissolveDelay;
        dissolve_status : ?Ver3.DissolveStatus;
        followee : ?Ver3.Followee;
    };

    public type Shared = {
        variables : {
            dissolve_delay : Ver3.DissolveDelay;
            dissolve_status : Ver3.DissolveStatus;
            followee : Ver3.Followee;
        };
        internals : {
            updating : Ver3.UpdatingStatus;
            local_idx : Nat32;
            refresh_idx : ?Nat64;
            spawning_neurons : [SharedNeuronCache];
        };
        cache : SharedNeuronCache;
        log : [Ver3.Activity];
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
    };

    public type Neuron = GovT.Neuron;

    public type NeuronInfo = GovT.NeuronInfo;

};
