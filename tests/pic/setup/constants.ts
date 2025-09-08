import { Principal } from "@dfinity/principal";
import { resolve } from "node:path";

export const GOVERNANCE_CANISTER_ID = Principal.fromText(
  "rrkah-fqaaa-aaaaa-aaaaq-cai"
);

export const ICP_LEDGER_CANISTER_ID = Principal.fromText(
  "ryjl3-tyaaa-aaaaa-aaaba-cai"
);

export const NNS_ROOT_CANISTER_ID = Principal.fromText(
  "r7inp-6aaaa-aaaaa-aaabq-cai"
);

export const MOCK_HOTKEY_TO_SET = Principal.fromText(
  "mxst2-5rf7k-unrqz-ojvao-p4jud-kra3z-3hwuk-lhduh-d7kv7-pfjvh-6qe"
);

export const MOCK_HOTKEY_TO_SET_2 = Principal.fromText(
  "slmx6-767wr-6blue-lximp-562bk-76ekl-3cxzi-dwtwd-y3lsy-ivl5e-vae"
);

export const NNS_STATE_PATH = resolve(__dirname, "..", "nns_state");

//
// helper constants:
//

export const EXPECTED_STAKE: bigint = 20_0000_0000n;

export const ICP_TRANSACTION_FEE: bigint = 10_000n;

export const EXPECTED_TRANSACTION_FEES: bigint = ICP_TRANSACTION_FEE * 2n;

export const AMOUNT_TO_STAKE: bigint =
  EXPECTED_STAKE + EXPECTED_TRANSACTION_FEES;

export const SPLIT_AMOUNT: bigint = 20_0000_0000n;

 export const STAKE_MULTIPLIER_FOR_SPLIT: bigint = 20n;

export const MINIMUM_DISSOLVE_DELAY_DAYS: bigint = 184n;

export const MAX_DISSOLVE_DELAY_DAYS: bigint = 2922n;

export const MOCK_FOLLOWEE_TO_SET: bigint = 6914974521667616512n;

export const MOCK_FOLLOWEE_TO_SET_2: bigint = 8571487073262291504n;
