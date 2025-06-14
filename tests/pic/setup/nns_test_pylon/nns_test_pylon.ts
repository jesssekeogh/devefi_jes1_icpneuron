import { resolve } from "node:path";
import { PocketIc } from "@dfinity/pic";
import { IDL } from "@dfinity/candid";
import {
  _SERVICE as NNSTESTPYLON,
  idlFactory,
  init as PylonInit,
} from "./declarations/nns_test_pylon.did.js";

const WASM_PATH = resolve(__dirname, "../nns_test_pylon/nns_test_pylon.wasm.gz");

export async function NnsTestPylon(pic: PocketIc) {
  const subnets = await pic.getApplicationSubnets();

  const fixture = await pic.setupCanister<NNSTESTPYLON>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(PylonInit({ IDL }), []),
    targetSubnetId: subnets[0].id,
  });

  return fixture;
}

export default NnsTestPylon;
