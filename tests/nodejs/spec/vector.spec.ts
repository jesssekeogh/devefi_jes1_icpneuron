import { type _SERVICE } from "../declarations/nnsvector.did";
import { idlFactory } from "../declarations/index";
import { resolve } from "node:path";
import { Principal } from "@dfinity/principal";
import { Actor, PocketIc, createIdentity } from "@hadronous/pic";

const WASM_PATH = resolve(
  __dirname,
  "..",
  "..",
  ".dfx",
  "canisters",
  "nnsvector",
  "nnsvector.wasm"
);

describe("Claim neuron suite", () => {
  let pic: PocketIc;
  let canisterId: Principal;
  let actor: Actor<_SERVICE>;

  beforeAll(async () => {
    pic = await PocketIc.create(process.env.PIC_URL);

    const fixture = await pic.setupCanister<_SERVICE>({
      idlFactory,
      wasm: WASM_PATH,
    });

    actor = fixture.actor;
    canisterId = fixture.canisterId;
    console.log(fixture)
  });

  afterAll(async () => {
    // tear down the PocketIC instance
    await pic.tearDown();
  });

  // it('should do something cool', async () => {
  //   const response = await actor();

  //   expect(response).toEqual('cool');
  // });

});
