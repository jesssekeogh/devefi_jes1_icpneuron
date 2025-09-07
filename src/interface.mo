import Ver4 "./memory/v4";
import GovT "mo:neuro/interfaces/nns_interface";

module {

    public type CreateRequest = {
        variables : {
            dissolve_delay : Ver4.DissolveDelay;
            dissolve_status : Ver4.DissolveStatus;
            followee : Ver4.Followee;
            hotkey : Ver4.Hotkey;
            visibility : Ver4.Visibility;
        };
    };

    public type ModifyRequest = {
        dissolve_delay : ?Ver4.DissolveDelay;
        dissolve_status : ?Ver4.DissolveStatus;
        followee : ?Ver4.Followee;
        hotkey : ?Ver4.Hotkey;
        visibility : ?Ver4.Visibility;
    };

    public type Shared = {
        variables : {
            dissolve_delay : Ver4.DissolveDelay;
            dissolve_status : Ver4.DissolveStatus;
            followee : Ver4.Followee;
            hotkey : Ver4.Hotkey;
            visibility : Ver4.Visibility;
        };
        internals : {
            updating : Ver4.UpdatingStatus;
            local_idx : Nat32;
            refresh_idx : ?Nat64;
            neuron_claimed : Bool;
            spawning_neurons : [SharedNeuronCache];
        };
        cache : SharedNeuronCache;
        neuron_cache : [SharedNeuronCache];
        log : [Ver4.Activity];
    };

    public type SharedNeuronCache = Ver4.SharedNeuronCache;

    public type Neuron = GovT.Neuron;

    public type NeuronInfo = GovT.NeuronInfo;

};