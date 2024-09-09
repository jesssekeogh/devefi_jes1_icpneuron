import Result "mo:base/Result";
import Node "mo:devefi/node";
import ICRC55 "mo:devefi/ICRC55";

module {

    public func meta(all_ledgers : [ICRC55.SupportedLedger]) : ICRC55.NodeMeta {
        {
            id = "stake";
            name = "Stake";
            description = "Stake neurons and receive maturity";
            governed_by = "Neutrinite DAO";
            supported_ledgers = all_ledgers;
            pricing = "0.0001 ICP";
        };
    };

    // Internal vector state
    public type Mem = {
        init : {
            ledger : Principal;
            neuron_controller : Principal; // needs to be canister
        };
        states : {
            var nonce : ?Nat64; // random bytes created (we need the nonce if it fails)
            var neuronSubaccount : ?Blob; // icp amount has been sent to the neuron subaccount account
            var neuronId : ?Nat64; // neuron has been claimed
        };
        events : {
            var maturity_extracted : ?Nat64;
        };
    };

    public type CreateRequest = {
        init : {
            ledger : Principal;
            neuron_controller : Principal;
        };
        states : {
            nonce : ?Nat64;
            neuronSubaccount : ?Blob;
            neuronId : ?Nat64;
        };
        events : {
            maturity_extracted : ?Nat64;
        };
    };

    public func CreateRequest2Mem(t : CreateRequest) : Mem {
        {
            init = t.init;
            states = {
                var nonce = t.states.nonce;
                var neuronSubaccount = t.states.neuronSubaccount;
                var neuronId = t.states.neuronId;
            };
            events = {
                var maturity_extracted = t.events.maturity_extracted;
            };
        };
    };

    public type ModifyRequest = {

    };

    public func ModifyRequestMut(mem : Mem, t : ModifyRequest) : Result.Result<(), Text> {
        #ok();
    };

    public type Shared = {
        init : {
            ledger : Principal;
            neuron_controller : Principal;
        };
        states : {
            nonce : ?Nat64;
            neuronSubaccount : ?Blob;
            neuronId : ?Nat64;
        };
        events : {
            maturity_extracted : ?Nat64;
        };
    };

    public func toShared(t : Mem) : Shared {
        {
            init = t.init;
            states = {
                nonce = t.states.nonce;
                neuronSubaccount = t.states.neuronSubaccount;
                neuronId = t.states.neuronId;
            };
            events = {
                maturity_extracted = t.events.maturity_extracted;
            };
        };
    };

    // Mapping of source node ports
    public func Request2Sources(t : Mem, id : Node.NodeId, thiscan : Principal) : Result.Result<[ICRC55.Endpoint], Text> {
        #ok([
            #ic {
                ledger = t.init.ledger;
                account = {
                    owner = thiscan;
                    subaccount = ?Node.port2subaccount({
                        vid = id;
                        flow = #input;
                        id = 0;
                    });
                };
            }
        ]);
    };

    // Mapping of destination node ports
    //
    // Allows you to change destinations and dynamically create new ones based on node state upon creation or modification
    // Fills in the account field when destination accounts are given
    // or leaves them null when not given
    public func Request2Destinations(t : Mem, req : [ICRC55.DestinationEndpoint]) : Result.Result<[ICRC55.DestinationEndpoint], Text> {
        let dest_0_account : ?ICRC55.Account = do {
            if (req.size() >= 1) {
                let #ic(x) = req[0] else return #err("Invalid destination 0");
                if (x.ledger != t.init.ledger) {
                    return #err("Invalid destination 0 ledger");
                };
                x.account;
            } else {
                null;
            };
        };
        #ok([
            #ic {
                ledger = t.init.ledger;
                account = dest_0_account;
            }
        ]);
    };
};
