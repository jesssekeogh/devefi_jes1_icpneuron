import ICRC55 "mo:devefi/ICRC55";
import Core "mo:devefi/core";
import NNSVector "../../src";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

module {

    public type CreateRequest = {
        #nns : NNSVector.Interface.CreateRequest;
    };

    public type Shared = {
        #nns : NNSVector.Interface.Shared;
    };

    public type ModifyRequest = {
        #nns : NNSVector.Interface.ModifyRequest;
    };

    public class VectorModules(
        m : {
            vec_nns : NNSVector.Mod;
        }
    ) {

        public func get(mid : Core.ModuleId, id : Core.NodeId) : Result.Result<Shared, Text> {

            if (mid == NNSVector.ID) {
                switch (m.vec_nns.get(id)) {
                    case (#ok(x)) return #ok(#nns(x));
                    case (#err(x)) return #err(x);
                };
            };

            #err("Unknown variant");
        };

        public func getDefaults(mid : Core.ModuleId) : CreateRequest {
            if (mid == NNSVector.ID) return #nns(m.vec_nns.defaults());
            Debug.trap("Unknown variant");

        };

        public func sources(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == NNSVector.ID) return m.vec_nns.sources(id);
            Debug.trap("Unknown variant");

        };

        public func destinations(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == NNSVector.ID) return m.vec_nns.destinations(id);
            Debug.trap("Unknown variant");
        };

        public func create(id : Core.NodeId, req : CreateRequest) : Result.Result<Core.ModuleId, Text> {

            switch (req) {
                case (#nns(t)) return m.vec_nns.create(id, t);
            };
            #err("Unknown variant or mismatch");
        };

        public func modify(mid : Core.ModuleId, id : Core.NodeId, creq : ModifyRequest) : Result.Result<(), Text> {
            switch (creq) {
                case (#nns(r)) if (mid == NNSVector.ID) return m.vec_nns.modify(id, r);
            };
            #err("Unknown variant or mismatch");
        };

        public func delete(mid : Core.ModuleId, id : Core.NodeId) : () {
            if (mid == NNSVector.ID) return m.vec_nns.delete(id);
            Debug.trap("Unknown variant");
        };

        public func nodeMeta(mid : Core.ModuleId) : ICRC55.ModuleMeta {
            if (mid == NNSVector.ID) return m.vec_nns.meta();
            Debug.trap("Unknown variant");
        };

        public func meta() : [ICRC55.ModuleMeta] {
            [
                m.vec_nns.meta(),
            ];
        };

    };
};
