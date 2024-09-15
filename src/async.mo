import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat64 "mo:base/Nat64";
import Random "mo:base/Random";
import S "./stake";
import { NNS } "mo:neuro";

module {

    public func get_now_nanos() : Nat64 {
        return Time.now() |> Int.abs(_) |> Nat64.fromNat(_);
    };

    public func generate_nonce(nodeMem : S.Mem, timeout : Nat64) : async () {
        switch (nodeMem.internals.generate_nonce) {
            case (#Init) {
                nodeMem.internals.generate_nonce := #Calling(get_now_nanos());

                // generate a random nonce that fits into Nat64
                let ?nonce = Random.Finite(await Random.blob()).range(64) else return;

                nodeMem.internals.generate_nonce := #Done(Nat64.fromNat(nonce));
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    nodeMem.internals.generate_nonce := #Calling(get_now_nanos());

                    let ?nonce = Random.Finite(await Random.blob()).range(64) else return;

                    nodeMem.internals.generate_nonce := #Done(Nat64.fromNat(nonce));
                };
            };
            case _ { return };
        };
    };

    public func claim_neuron(nodeMem : S.Mem, timeout : Nat64, canisterId : Principal, nnsId : Principal, icpId : Principal) : async () {
        let #Done(nonce) = nodeMem.internals.generate_nonce else return;

        let nns = NNS.Governance({
            canister_id = canisterId;
            nns_canister_id = nnsId;
            icp_ledger_canister_id = icpId;
        });

        switch (nodeMem.internals.claim_neuron) {
            case (#Init) {
                nodeMem.internals.claim_neuron := #Calling(get_now_nanos());

                let #ok(neuronId) = await nns.claimNeuron({ nonce = nonce }) else return;
                nodeMem.internals.claim_neuron := #Done(neuronId);
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    nodeMem.internals.claim_neuron := #Calling(get_now_nanos());

                    let #ok(neuronId) = await nns.claimNeuron({ nonce = nonce }) else return;
                    nodeMem.internals.claim_neuron := #Done(neuronId);
                };
            };
            case _ { return };
        };
    };

    public func update_followee(nodeMem : S.Mem, timeout : Nat64, nnsId : Principal) : async () {
        let #Done(neuronId) = nodeMem.internals.claim_neuron else return;
        // TODO: follow topic 4 for governance
        // TODO: follow topic 14 for sns & community fund
        // follow 0 for all;

        let neuron = NNS.Neuron({
            nns_canister_id = nnsId;
            neuron_id = neuronId;
        });

        switch (nodeMem.internals.update_followee) {
            case (#Init) {
                let ?followee = nodeMem.variables.followee else return;

                nodeMem.internals.update_followee := #Calling(get_now_nanos());

                let #ok(_) = await neuron.follow({
                    topic = 0;
                    followee = followee;
                }) else return;
                nodeMem.internals.update_followee := #Done(followee);
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    let ?followee = nodeMem.variables.followee else return;

                    nodeMem.internals.update_followee := #Calling(get_now_nanos());

                    let #ok(_) = await neuron.follow({
                        topic = 0;
                        followee = followee;
                    }) else return;
                    nodeMem.internals.update_followee := #Done(followee);
                };
            };
            case _ { return };
        };
    };

    public func update_delay(nodeMem : S.Mem, timeout : Nat64, nnsId : Principal) : async () {
        let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

        let neuron = NNS.Neuron({
            nns_canister_id = nnsId;
            neuron_id = neuronId;
        });

        switch (nodeMem.internals.update_delay) {
            case (#Init) {
                let ?dissolveTimestamp = nodeMem.variables.dissolve_timestamp_seconds else return

                nodeMem.internals.update_delay := #Calling(get_now_nanos());

                let #ok(_) = await neuron.setDissolveTimestamp({
                    dissolve_timestamp_seconds = dissolveTimestamp;
                }) else return;
                nodeMem.internals.update_delay := #Done(dissolveTimestamp);
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    let ?dissolveTimestamp = nodeMem.variables.dissolve_timestamp_seconds else return

                    nodeMem.internals.update_delay := #Calling(get_now_nanos());

                    let #ok(_) = await neuron.setDissolveTimestamp({
                        dissolve_timestamp_seconds = dissolveTimestamp;
                    }) else return;
                    nodeMem.internals.update_delay := #Done(dissolveTimestamp);
                };
            };
            case _ { return };
        };
    };

    public func add_hotkey(nodeMem : S.Mem, timeout : Nat64, nnsId : Principal) : async () {
        let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

        let neuron = NNS.Neuron({
            nns_canister_id = nnsId;
            neuron_id = neuronId;
        });

        switch (nodeMem.internals.add_hotkey) {
            case (#Init) {
                let ?hotkey = nodeMem.variables.hotkey else return

                nodeMem.internals.add_hotkey := #Calling(get_now_nanos());

                let #ok(_) = await neuron.addHotKey({ new_hot_key = hotkey }) else return;
                nodeMem.internals.add_hotkey := #Done(hotkey);
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    let ?hotkey = nodeMem.variables.hotkey else return;

                    nodeMem.internals.add_hotkey := #Calling(get_now_nanos());

                    let #ok(_) = await neuron.addHotKey({ new_hot_key = hotkey }) else return;
                    nodeMem.internals.add_hotkey := #Done(hotkey);
                };
            };
            case _ { return };
        };
    };

    public func remove_hotkey(nodeMem : S.Mem, timeout : Nat64, nnsId : Principal) : async () {
        let #Done(neuronId) = nodeMem.internals.claim_neuron else return;

        let neuron = NNS.Neuron({
            nns_canister_id = nnsId;
            neuron_id = neuronId;
        });

        switch (nodeMem.internals.remove_hotkey) {
            case (#Init) {
                let ?hotkeyToRemove = nodeMem.variables.hotkey_to_remove else return

                nodeMem.internals.remove_hotkey := #Calling(get_now_nanos());

                let #ok(_) = await neuron.removeHotKey({
                    hot_key_to_remove = hotkeyToRemove;
                }) else return;
                nodeMem.internals.remove_hotkey := #Done(hotkeyToRemove);
            };
            case (#Calling(startTime)) {
                if (get_now_nanos() - startTime >= timeout) {
                    let ?hotkeyToRemove = nodeMem.variables.hotkey_to_remove else return

                    nodeMem.internals.remove_hotkey := #Calling(get_now_nanos());

                    let #ok(_) = await neuron.removeHotKey({
                        hot_key_to_remove = hotkeyToRemove;
                    }) else return;
                    nodeMem.internals.remove_hotkey := #Done(hotkeyToRemove);
                };
            };
            case _ { return };
        };
    };
};
