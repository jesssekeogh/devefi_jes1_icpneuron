import { Principal } from "@dfinity/principal";
import { resolve } from "node:path";

export const GOVERNANCE_CANISTER_ID = Principal.fromText(
  "rrkah-fqaaa-aaaaa-aaaaq-cai"
);

export const ICP_LEDGER_CANISTER_ID = Principal.fromText(
  "ryjl3-tyaaa-aaaaa-aaaba-cai"
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
