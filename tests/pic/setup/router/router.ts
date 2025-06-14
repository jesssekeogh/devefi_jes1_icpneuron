import { resolve } from "node:path";
import { PocketIc } from "@dfinity/pic";
import { IDL } from "@dfinity/candid";
import {
  _SERVICE as ROUTER,
  idlFactory,
  init as PylonInit,
} from "./declarations/router.did.js";

const WASM_PATH = resolve(__dirname, "../router/router.wasm.gz");

export async function Router(pic: PocketIc) {
  const subnets = await pic.getApplicationSubnets();

  const fixture = await pic.setupCanister<ROUTER>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(PylonInit({ IDL }), []),
    targetSubnetId: subnets[0].id,
  });

  return fixture;
}

export default Router;
