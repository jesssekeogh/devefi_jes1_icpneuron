import { resolve } from "node:path";
import { PocketIc } from "@hadronous/pic";
import {
  _SERVICE as NNSVECTOR,
  idlFactory,
  init,
} from "../../declarations/nnsvector/nnsvector.did.js";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";

const WASM_PATH = resolve(
  __dirname,
  "..",
  "..",
  "..",
  "..",
  ".dfx",
  "ic",
  "canisters",
  "nnsvector",
  "nnsvector.wasm"
);

export async function NNSVector(
  pic: PocketIc,
  govcan: Principal,
  icpcan: Principal,
  ntncan: Principal
) {
  const fixture = await pic.setupCanister<NNSVECTOR>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(init({ IDL }), [
      {
        icp_governance: govcan,
        fee_ledger: ntncan,
        icp_ledger: icpcan,
      },
    ]),
  });

  return fixture;
}

export default NNSVector;
