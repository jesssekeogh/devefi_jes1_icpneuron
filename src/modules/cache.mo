import Option "mo:base/Option";
import Array "mo:base/Array";
import Ver4 "../memory/v4";
import U "mo:devefi/utils";
import Constants "../constants";

module CacheManager {

    public type IcpNeuronNodeMem = Ver4.NodeMem;

    public func delay_changed(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        let #Locked = nodeMem.variables.dissolve_status else return null;

        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;

            let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                case (#Default) { Constants.MINIMUM_DELAY_SECONDS };
                case (#DelayDays(days)) { days * Constants.ONE_DAY_SECONDS };
            };

            let ?cachedDelay = neuron.dissolve_delay_seconds else return neuronId;

            if (delayToSet > cachedDelay + Constants.DELAY_BUFFER_SECONDS) return neuronId;
        };

        return null;
    };

    public func following_changed(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;

            // If followees is empty and we expect something other than None
            if (neuron.followees.size() == 0) {
                switch (nodeMem.variables.followee) {
                    case (#None) { /* This is expected */ };
                    case (#Default or #FolloweeId(_)) {
                        return neuronId; // Mismatch: empty followees but expecting followees
                    };
                };
            } else {
                for ((topic, { followees }) in neuron.followees.vals()) {
                    switch (nodeMem.variables.followee) {
                        case (#None) {
                            if (followees.size() > 0) return neuronId;
                        };
                        case (#Default) {
                            if (followees[0].id != Constants.DEFAULT_NEURON_FOLLOWEE) return neuronId;
                        };
                        case (#FolloweeId(followee)) {
                            if (followees[0].id != followee) return neuronId;
                        };
                    };
                };
            };
        };

        return null;
    };

    public func dissolving_changed(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;

            let ?dissolvingState = neuron.state else return neuronId;

            switch (nodeMem.variables.dissolve_status) {
                case (#Dissolving) {
                    if (dissolvingState == Constants.NEURON_STATES.locked) return neuronId;
                };
                case (#Locked) {
                    if (dissolvingState == Constants.NEURON_STATES.dissolving) return neuronId;
                };
            };
        };

        return null;
    };

    public func hotkeys_changed(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        let #HotkeyIds(hotkeysToSet) = nodeMem.variables.hotkeys else return null;

        if (hotkeysToSet.size() > Constants.HOTKEY_LIMIT) return null;

        label hotkeyLoop for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;

            // Quick size check first - most common case
            if (neuron.hot_keys.size() != hotkeysToSet.size()) return neuronId;

            // If both are empty, they match
            if (neuron.hot_keys.size() == 0) continue hotkeyLoop;

            // Check if all hotkeys in the new set exist in current set
            for (hotkeyToSet in hotkeysToSet.vals()) {
                if (Option.isNull(Array.find(neuron.hot_keys, func(current : Principal) : Bool { current == hotkeyToSet }))) {
                    return neuronId; // not found, they're different
                };
            };
        };

        return null;
    };

    public func visibility_changed(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;
            let ?visibility = neuron.visibility else return null;

            switch (nodeMem.variables.visibility) {
                case (#Private) {
                    if (visibility != 1) return neuronId;
                };
                case (#Public) {
                    if (visibility != 2) return neuronId;
                };
            };
        };

        return null;
    };

    public func maturity_ready(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;
            let ?maturity = neuron.maturity_e8s_equivalent else return null;

            if (maturity > Constants.MINIMUM_SPAWN) return neuronId;
        };

        return null;
    };

    public func voting_power_stale(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;
            let ?votingPowerRefreshed = neuron.voting_power_refreshed_timestamp_seconds else return null;

            let nowSecs = U.now() / 1_000_000_000;

            if (nowSecs >= votingPowerRefreshed + Constants.TIMEOUT_REFRESH_VOTING_POWER_SECONDS) return neuronId;
        };

        return null;
    };

    public func neuron_ready_to_disburse(nodeMem : IcpNeuronNodeMem) : ?Nat64 {
        let #Dissolving = nodeMem.variables.dissolve_status else return null;

        for (neuron in nodeMem.neuron_cache.vals()) {
            let neuronId = neuron.neuron_id;
            let ?dissolvingState = neuron.state else return null;
            let ?cachedStake = neuron.cached_neuron_stake_e8s else return null;

            if (dissolvingState == Constants.NEURON_STATES.unlocked and cachedStake > 0) return neuronId;
        };

        return null;
    };

};
