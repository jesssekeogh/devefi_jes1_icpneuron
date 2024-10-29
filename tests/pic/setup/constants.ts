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

export const NNS_STATE_PATH = resolve(
  __dirname,
  "..",
  "nns_state",
  "node-100",
  "state"
);

export const NNS_SUBNET_ID =
  "5zbf7-w773a-srrlr-keamy-7pusd-nlghp-ml5pu-ivrne-y67rh-zkpyc-iqe";

//
// helper constants:
//

export const AMOUNT_TO_STAKE: bigint = 10_0000_0000n;

export const EXPECTED_TRANSACTION_FEES: bigint = 20_000n;

export const MINIMUM_DISSOLVE_DELAY: bigint = 15897600n;

export const ONE_YEAR_SECONDS: bigint =
  ((4n * 365n + 1n) * (24n * 60n * 60n)) / 4n;

export const MAX_DISSOLVE_DELAY: bigint = 8n * ONE_YEAR_SECONDS;

export const MOCK_FOLLOWEE_TO_SET: bigint = 6914974521667616512n;

export const MOCK_FOLLOWEE_TO_SET_2: bigint = 8571487073262291504n;
