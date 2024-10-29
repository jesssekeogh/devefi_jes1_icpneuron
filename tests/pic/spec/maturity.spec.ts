import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import { AMOUNT_TO_STAKE, MINIMUM_DISSOLVE_DELAY } from "../setup/constants.ts";

describe("Maturity", () => {
  let manager: Manager;
  let maturity: Maturity;
  let node: NodeShared;
  let maturityFollowee: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    maturityFollowee = await maturity.createNeuron();

    node = await manager.stakeNeuron(AMOUNT_TO_STAKE, {
      dissolveDelay: MINIMUM_DISSOLVE_DELAY,
      followee: maturityFollowee,
      dissolving: false,
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should accrue maturity", async () => {
    await maturity.createMotionProposal(maturityFollowee);
    await manager.advanceBlocksAndTime(1);

    await manager.advanceTime(20160); // 2 weeks
    await manager.advanceBlocks(10);

    await manager.advanceBlocksAndTime(1);
    node = await manager.getNode(node.id);

    expect(
      node.custom.nns_neuron.cache.maturity_e8s_equivalent[0]
    ).toBeGreaterThan(0n);
  });

  it("should spawn maturity", async () => {
    await manager.advanceBlocksAndTime(5);
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

    await manager.advanceBlocksAndTime(5);

    node = await manager.getNode(node.id);
    expect(node.custom.nns_neuron.internals.spawning_neurons.length).toBe(0);

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
});
