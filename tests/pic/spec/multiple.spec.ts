import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import { createIdentity } from "@hadronous/pic";
import { Setup } from "../setup/setup.ts";

describe("Multiple", () => {
  let setup: Setup;
  let manager: Manager;
  let maturity: Maturity;
  let managers: Manager[];
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let isDissolving: boolean = false;
  let followeeNeuronId: bigint;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
    let me = createIdentity("superSecretAlicePassword");

    manager = await Manager.beforeAll(setup.getPicInstance(), me);

    maturity = Maturity.beforeAll(manager);

    followeeNeuronId = await maturity.createNeuron();

    // setup some more identitys

    let identitys = [
      createIdentity("x"),
      createIdentity("y"),
      createIdentity("z"),
    ];

    managers = await Promise.all(
      identitys.map(async (identity) => {
        return await Manager.beforeAll(setup.getPicInstance(), identity);
      })
    );
  });

  afterAll(async () => {});

  it("should stake multiple neurons", async () => {});

  it("should update multiple neurons", async () => {});

  it("should increase multiple neurons stake", async () => {});

  it("should accrue maturity in multiple neurons", async () => {});

  it("should spawn maturity in multiple neurons", async () => {});

  it("should claim maturity from multiple neurons", async () => {});

  it("should disburse multiple neurons", async () => {});
});
