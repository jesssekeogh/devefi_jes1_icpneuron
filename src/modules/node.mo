import Option "mo:base/Option";
import Buffer "mo:base/Buffer";
import Nat64 "mo:base/Nat64";
import Core "mo:devefi/core";
import U "mo:devefi/utils";
import Ver4 "../memory/v4";
import CacheManager "./cache";
import Constants "../constants";

module NodeUtils {

    public type IcpNeuronNodeMem = Ver4.NodeMem;

    let T = Core.VectorModule;

    public func node_ready(nodeMem : IcpNeuronNodeMem) : Bool {
        // Determine the appropriate timeout based on whether the neuron should be refreshed
        let timeout = if (node_needs_refresh(nodeMem)) {
            Constants.TIMEOUT_NANOS_REFRESH_PENDING;
        } else {
            Constants.TIMEOUT_NANOS_NO_REFRESH_PENDING;
        };

        switch (nodeMem.internals.updating) {
            case (#Init) {
                nodeMem.internals.updating := #Calling(U.now());
                return true;
            };
            case (#Calling(ts) or #Done(ts)) {
                if (U.now() >= ts + timeout) {
                    nodeMem.internals.updating := #Calling(U.now());
                    return true;
                } else {
                    return false;
                };
            };
        };
    };

    private func node_needs_refresh(nodeMem : IcpNeuronNodeMem) : Bool {
        return (
            Option.isSome(nodeMem.internals.refresh_idx) or
            Option.isSome(CacheManager.following_changed(nodeMem)) or
            Option.isSome(CacheManager.dissolving_changed(nodeMem)) or
            Option.isSome(CacheManager.delay_changed(nodeMem)) or
            Option.isSome(CacheManager.hotkeys_changed(nodeMem)) or
            Option.isSome(CacheManager.visibility_changed(nodeMem)) or
            Option.isSome(CacheManager.maturity_ready(nodeMem)) or
            Option.isSome(CacheManager.voting_power_stale(nodeMem)) or
            Option.isSome(CacheManager.neuron_ready_to_disburse(nodeMem))
        );
    };

    public func node_done(nodeMem : IcpNeuronNodeMem) : () {
        nodeMem.internals.updating := #Done(U.now());
    };

    public func tx_sent(nodeMem : IcpNeuronNodeMem, txId : Nat64) : () {
        nodeMem.internals.refresh_idx := ?txId;
    };

    public func log_activity(nodeMem : IcpNeuronNodeMem, operation : Text, result : { #Ok; #Err : Text }) : () {
        let log = Buffer.fromArray<Ver4.Activity>(nodeMem.log);

        switch (result) {
            case (#Ok(())) {
                log.add(#Ok({ operation = operation; timestamp = U.now() }));
            };
            case (#Err(msg)) {
                log.add(#Err({ operation = operation; msg = msg; timestamp = U.now() }));
            };
        };

        if (log.size() > Constants.ACTIVITY_LOG_LIMIT) {
            ignore log.remove(0); // remove 1 item from the beginning
        };

        nodeMem.log := Buffer.toArray(log);
    };

    public func get_neuron_nonce(vid : T.NodeId, localId : Nat32) : Nat64 {
        return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
    };
};
