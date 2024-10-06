import { test; expect } "mo:test";
import U "../../src/utils";
import Set "mo:map/Set";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";

test(
    "test unique nonce generation",
    func() {
        let TOTAL_NODES : Nat32 = 1000;
        let TOTAL_SPAWNS_PER_NODE : Nat32 = 100;

        let nonces = Set.new<Nat64>();

        var vid : Nat32 = 0;
        while (vid < TOTAL_NODES) {

            var idx : Nat32 = 0;
            while (idx < TOTAL_SPAWNS_PER_NODE) {
                let newNonce = U.get_neuron_nonce(vid, idx);

                let exists = Set.put(nonces, Set.n64hash, newNonce);
                expect.bool(exists).isFalse();
                idx += 1;
            };

            vid += 1;
        };

        let totalNonces = Set.size(nonces);
        Debug.print("Total neuron nonces tested: " # debug_show totalNonces);

        let expectedTotal = TOTAL_NODES * TOTAL_SPAWNS_PER_NODE;
        expect.nat(totalNonces).equal(Nat32.toNat(expectedTotal));
    },
);
