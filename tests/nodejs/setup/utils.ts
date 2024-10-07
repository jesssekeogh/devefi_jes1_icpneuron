import { type _SERVICE as NNSVECTOR } from "../declarations/nnsvector/nnsvector.did";
import { idlFactory } from "../declarations/nnsvector/index";
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

export async function PylonCan(pic: PocketIc) {
  const fixture = await pic.setupCanister<NNSVECTOR>({
    idlFactory: idlFactory,
    wasm: WASM_PATH,
  });

  return fixture;
}

export function DF() {
  return {
    pic: undefined as PocketIc,
    // ledger: undefined as Actor<ICRCLedgerService>,
    pylon: undefined as Actor<NNSVECTOR>,
    userCanisterId: undefined as Principal,
    // ledgerCanisterId: undefined as Principal,
    pylonCanisterId: undefined as Principal,
    // u: undefined as ReturnType<typeof createNodeUtils>,
    jo: undefined as ReturnType<typeof createIdentity>,
    ledger_fee: undefined as bigint,
    async passTime(n: number): Promise<void> {
      if (!this.pic) throw new Error("PocketIc is not initialized");
      for (let i = 0; i < n; i++) {
        await this.pic.advanceTime(3 * 1000);
        await this.pic.tick(6);
      }
    },
    async passTimeMinute(n: number): Promise<void> {
      if (!this.pic) throw new Error("PocketIc is not initialized");
      await this.pic.advanceTime(n * 60 * 1000);
      await this.pic.tick(6);
      // await this.passTime(5)
    },

    async beforeAll(): Promise<void> {
      this.jo = createIdentity("superSecretAlicePassword");

      // Initialize PocketIc
      this.pic = await PocketIc.create(process.env.PIC_URL);

      // // Ledger initialization
      // const ledgerFixture = await ICRCLedger(this.pic, this.jo.getPrincipal(), undefined); // , this.pic.getSnsSubnet()?.id
      // this.ledger = ledgerFixture.actor;
      // this.ledgerCanisterId = ledgerFixture.canisterId;
      // this.ledger_fee = await this.ledger.icrc1_fee();

      // await this.pic.addCycles(this.ledgerCanisterId, 100_000_000_000_000);
      // Pylon canister initialization
      const pylonFixture = await PylonCan(this.pic);
      this.pylon = pylonFixture.actor;
      this.pylonCanisterId = pylonFixture.canisterId;
      await this.pic.addCycles(this.pylonCanisterId, 100_000_000_000_000);
      // Setup interactions between ledger and pylon
      // await this.pylon.add_supported_ledger(this.ledgerCanisterId, { icrc: null });
      await this.pylon.start();

      // Set the identity for ledger and pylon
      // this.ledger.setIdentity(this.jo);
      this.pylon.setIdentity(this.jo);

      // Initialize node utilities
      //   this.u = createNodeUtils({
      //     ledger: this.ledger,
      //     pylon: this.pylon,
      //     ledgerCanisterId: this.ledgerCanisterId,
      //     pylonCanisterId: this.pylonCanisterId,
      //     user: this.jo.getPrincipal(),
      //   });

      // Advance time to sync with initialization
      await this.passTime(10);
    },

    async afterAll(): Promise<void> {
      if (!this.pic) throw new Error("PocketIc is not initialized");
      await this.pic.tearDown();
    },
  };
}
