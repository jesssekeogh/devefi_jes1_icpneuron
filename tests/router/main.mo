import Router "mo:chronotrinite/router";
import Principal "mo:base/Principal";

actor this {

    stable let router_v1 = Router.Mem.ChronoRouter.V1.new();
    let router = Router.ChronoRouter<system>({
        xmem = router_v1;
        me = Principal.fromActor(this);
    });

    public query func get_slices() : async Router.GetSlicesResp {
        router.get_slices();
    };

    public query func show_log() : async [?Text] {
        router.show_log();
    };

    public query func canister_info() : async Router.CanisterInfo {
        router.canister_info();
    };

    public shared({caller}) func set_access(req : Router.SetAccessRequest) : async () {
        router.set_access<system>(caller, req);
    };

};