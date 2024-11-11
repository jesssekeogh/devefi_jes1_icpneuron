import ICRC55 "mo:devefi/ICRC55";
import Core "mo:devefi/core";
import IcpNeuronVector "../../src";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

module {

    public type CreateRequest = {
        #devefi_jes1_icpneuron : IcpNeuronVector.Interface.CreateRequest;
    };

    public type Shared = {
        #devefi_jes1_icpneuron : IcpNeuronVector.Interface.Shared;
    };

    public type ModifyRequest = {
        #devefi_jes1_icpneuron : IcpNeuronVector.Interface.ModifyRequest;
    };

    public class VectorModules(
        m : {
            devefi_jes1_icpneuron : IcpNeuronVector.Mod;
        }
    ) {

        public func get(mid : Core.ModuleId, id : Core.NodeId, vec : Core.NodeMem) : Result.Result<Shared, Text> {

            if (mid == IcpNeuronVector.ID) {
                switch (m.devefi_jes1_icpneuron.get(id, vec)) {
                    case (#ok(x)) return #ok(#devefi_jes1_icpneuron(x));
                    case (#err(x)) return #err(x);
                };
            };

            #err("Unknown variant");
        };

        public func getDefaults(mid : Core.ModuleId) : CreateRequest {
            if (mid == IcpNeuronVector.ID) return #devefi_jes1_icpneuron(m.devefi_jes1_icpneuron.defaults());
            Debug.trap("Unknown variant");

        };

        public func sources(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == IcpNeuronVector.ID) return m.devefi_jes1_icpneuron.sources(id);
            Debug.trap("Unknown variant");

        };

        public func destinations(mid : Core.ModuleId, id : Core.NodeId) : Core.EndpointsDescription {
            if (mid == IcpNeuronVector.ID) return m.devefi_jes1_icpneuron.destinations(id);
            Debug.trap("Unknown variant");
        };

        public func create(id : Core.NodeId, creq : Core.CommonCreateRequest, req : CreateRequest) : Result.Result<Core.ModuleId, Text> {

            switch (req) {
                case (#devefi_jes1_icpneuron(t)) return m.devefi_jes1_icpneuron.create(id, creq, t);
            };
            #err("Unknown variant or mismatch");
        };

        public func modify(mid : Core.ModuleId, id : Core.NodeId, creq : ModifyRequest) : Result.Result<(), Text> {
            switch (creq) {
                case (#devefi_jes1_icpneuron(r)) if (mid == IcpNeuronVector.ID) return m.devefi_jes1_icpneuron.modify(id, r);
            };
            #err("Unknown variant or mismatch");
        };

        public func delete(mid : Core.ModuleId, id : Core.NodeId) : Result.Result<(), Text> {
            if (mid == IcpNeuronVector.ID) return m.devefi_jes1_icpneuron.delete(id);
            Debug.trap("Unknown variant");
        };

        public func nodeMeta(mid : Core.ModuleId) : ICRC55.ModuleMeta {
            if (mid == IcpNeuronVector.ID) return m.devefi_jes1_icpneuron.meta();
            Debug.trap("Unknown variant");
        };

        public func meta() : [ICRC55.ModuleMeta] {
            [
                m.devefi_jes1_icpneuron.meta(),
            ];
        };

    };
};
