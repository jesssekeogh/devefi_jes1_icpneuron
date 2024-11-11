import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  MAX_DISSOLVE_DELAY,
  MINIMUM_DISSOLVE_DELAY,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";

describe("Errors", () => {
  let manager: Manager;
  let node: NodeShared;
  let defaultDelay: bigint = 0n;
  let defaultFollowee: bigint = 0n;
  let belowMinimumStake: bigint = AMOUNT_TO_STAKE - AMOUNT_TO_STAKE / 2n;

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    node = await manager.stakeNeuron(belowMinimumStake, {
      dissolveDelay: defaultDelay,
      followee: defaultFollowee,
      dissolving: { KeepLocked: null },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should not stake neuron if below minimum", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeUndefined();
    expect(node.sources[0].balance).toBeGreaterThan(0n);
  });

  it("should set minimum delay when variable is below minimum", async () => {
    // process stake
    await manager.sendIcp(
      manager.getNodeSourceAccount(node, 0),
      AMOUNT_TO_STAKE
    );

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(MINIMUM_DISSOLVE_DELAY);
  });

  it("should set maximum delay when variable exceeds maximum", async () => {
    let aboveMaximum = MAX_DISSOLVE_DELAY + MINIMUM_DISSOLVE_DELAY;
    await manager.modifyNode(node.id, [aboveMaximum], [], []);

    await manager.advanceBlocksAndTimeMinutes(3);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(MAX_DISSOLVE_DELAY);
  });

  it("should set the default followee", async () => {
    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET); // mock followee is rakeoff (which is default)
    }
  });

  it("should error when attempting to delete a node with a neuron", async () => {
    await expect(manager.deleteNode(node.id)).rejects.toThrow(
      "Neuron is not empty"
    );
  });
});
