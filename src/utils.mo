import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int "mo:base/Int";

module {

    public func get_neuron_nonce(vid : Nat32, localId : Nat32) : Nat64 {
        return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
    };

    public func get_now_nanos() : Nat64 {
        return Time.now() |> Int.abs(_) |> Nat64.fromNat(_);
    };

};
