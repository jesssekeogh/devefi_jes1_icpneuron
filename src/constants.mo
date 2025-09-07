module Constants {

    public let NNS_CANISTER_ID : Text = "rrkah-fqaaa-aaaaa-aaaaq-cai";

    public let ICP_LEDGER_CANISTER_ID : Text = "ryjl3-tyaaa-aaaaa-aaaba-cai";

    // Interval for cache check when no neuron refresh is pending.
    // Maturity accumulates only once per day, allowing at most one neuron spawn daily.
    public let TIMEOUT_NANOS_NO_REFRESH_PENDING : Nat64 = 43200000000000;

    // Timeout interval for when a neuron refresh is pending.
    public let TIMEOUT_NANOS_REFRESH_PENDING : Nat64 = 180000000000; // every 3 minutes

    public let DEFAULT_NEURON_FOLLOWEE : Nat64 = 6914974521667616512; // Rakeoff.io named neuron

    // 20.00 ICP in e8s
    public let MINIMUM_STAKE : Nat = 2_000_000_000;

    // 20.00 ICP in e8s
    public let MINIMUM_SPLIT : Nat64 = 2_000_000_000;

    // 1.06 ICP in e8s
    public let MINIMUM_SPAWN : Nat64 = 106_000_000;

    // Maximum number of activities to keep in the main neuron's activity log
    public let ACTIVITY_LOG_LIMIT : Nat = 10;

    // Used to calculate days as seconds for delay inputs
    public let ONE_DAY_SECONDS : Nat64 = 86400;

    // Minimum dissolve delay to vote and earn rewards
    public let MINIMUM_DELAY_SECONDS : Nat64 = 15897600; // 184 days in seconds

    // Minimum allowable delay increase, defined as a buffer of two weeks (in seconds)
    public let DELAY_BUFFER_SECONDS : Nat64 = 1209600; // 14 days in seconds

    // From here: https://github.com/dfinity/ic/blob/master/rs/nervous_system/common/src/lib.rs#L67C15-L67C27
    public let ONE_YEAR_SECONDS : Nat64 = 31557600; // (4 * 365 + 1) * 86400 / 4 = 31557600 seconds in a year

    // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/src/governance.rs#L164
    public let MAXIMUM_DELAY_SECONDS : Nat64 = 252460800; // 8 years in seconds (8 * 31557600)

    // Timeout interval for when a neurons voting power needs to be refreshed
    public let TIMEOUT_REFRESH_VOTING_POWER_SECONDS : Nat64 = 7776000; // every 90 days (90 * 86400 seconds)

    // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L41
    public let GOVERNANCE_TOPICS : [Int32] = [
        0, // Catch all, except Governance & SNS & Community Fund
        4, // Governance
        14, // SNS & Community Fund
    ];

    // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L149
    public let NEURON_STATES = {
        locked : Int32 = 1;
        dissolving : Int32 = 2;
        unlocked : Int32 = 3;
        spawning : Int32 = 4;
    };
};
