import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import { createIdentity } from "@hadronous/pic";
import { Setup } from "../setup/setup.ts";

describe("Maturity", () => {
  let setup: Setup;
  let manager: Manager;
  let maturity: Maturity;
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

    node = await manager.stakeNeuron(amountToStake, {
      dissolveDelay: dissolveDelayToSet,
      followee: followeeNeuronId,
      dissolving: isDissolving,
    });
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should accrue maturity", async () => {
    await maturity.createMotionProposal(followeeNeuronId);
    await manager.advanceBlocksAndTime(5);

    await manager.advanceTime(20160); // 2 weeks
    await manager.advanceBlocks(10);

    node = await manager.getNode(node.id);

    expect(
      node.custom.nns_neuron.cache.maturity_e8s_equivalent[0]
    ).toBeGreaterThan(0n);
  });

  it("should spawn maturity", async () => {
    await manager.advanceBlocksAndTime(10);
    node = await manager.getNode(node.id);

    expect(
      node.custom.nns_neuron.internals.spawning_neurons.length
    ).toBeGreaterThan(0);
    expect(node.custom.nns_neuron.internals.local_idx).toBe(1);
  });

  it("should claim maturity", async () => {
    let oldBalance = await manager.getMyBalances();
    await manager.advanceTime(10160); // 1 week
    await manager.advanceBlocks(10);

    await manager.advanceBlocksAndTime(10);

    node = await manager.getNode(node.id);
    expect(node.custom.nns_neuron.internals.spawning_neurons.length).toBe(0);

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
});
