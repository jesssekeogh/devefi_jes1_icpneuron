import Result "mo:base/Result";
import Node "mo:devefi/node";
import StakeVector "./stake";
import ICRC55 "mo:devefi/ICRC55";
import Debug "mo:base/Debug";

module {

    public type CreateRequest = {
        #stake : StakeVector.CreateRequest;
    };

    public type Mem = {
        #stake : StakeVector.Mem;
    };

    public type Shared = {
        #stake : StakeVector.Shared;
    };

    public type ModifyRequest = {
        #stake : StakeVector.ModifyRequest;
    };

    public func toShared(node : Mem) : Shared {
        switch (node) {
            case (#stake(t)) #stake(StakeVector.toShared(t));
        };
    };

    public func getDefaults(id:Text, all_ledgers : [ICRC55.SupportedLedger]) : CreateRequest {
        switch(id) {
            case ("stake") #stake(StakeVector.defaults(all_ledgers));
            case (_) Debug.trap("Unknown variant");
        };
    };

    public func sourceMap(id : Node.NodeId, custom : Mem, thiscan : Principal) : Result.Result<[ICRC55.Endpoint], Text> {
        switch (custom) {
            case (#stake(t)) StakeVector.Request2Sources(t, id, thiscan);
            //...
        };
    };

    public func destinationMap(custom : Mem, destinationsProvided : [ICRC55.DestinationEndpoint]) : Result.Result<[ICRC55.DestinationEndpoint], Text> {
        switch (custom) {
            case (#stake(t)) StakeVector.Request2Destinations(t, destinationsProvided);
            //...
        };
    };

    public func createRequest2Mem(req : CreateRequest) : Mem {
        switch (req) {
            case (#stake(t)) #stake(StakeVector.CreateRequest2Mem(t));
            //...
        };
    };

    public func modifyRequestMut(custom : Mem, creq : ModifyRequest) : Result.Result<(), Text> {
        switch (custom, creq) {
            case (#stake(t), #stake(r)) StakeVector.ModifyRequestMut(t, r);
            //...
        };
    };

    public func meta(all_ledgers : [ICRC55.SupportedLedger]) : [ICRC55.NodeMeta] {
        [
            StakeVector.meta(all_ledgers),
            //...
        ];
    };
};
