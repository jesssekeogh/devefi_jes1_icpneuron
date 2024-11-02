import { resolve } from "node:path";
import { PocketIc } from "@hadronous/pic";
import { IDL } from "@dfinity/candid";
import {
  _SERVICE as NNSVECTOR,
  idlFactory,
  init as PylonInit,
} from "../../declarations/nnsvector/nnsvector.did.js";

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

export async function NNSVector(pic: PocketIc) {
  const fixture = await pic.setupCanister<NNSVECTOR>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(PylonInit({ IDL }), []),
  });

  return fixture;
}

export default NNSVector;
