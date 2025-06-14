import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import {
  AMOUNT_TO_STAKE,
  MAX_DISSOLVE_DELAY_DAYS,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";

describe("Errors", () => {
  let manager: Manager;
  let node: NodeShared;
  let belowMinimumStake: bigint = AMOUNT_TO_STAKE - AMOUNT_TO_STAKE / 2n;

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    node = await manager.stakeNeuron({
      stake_amount: belowMinimumStake,
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { Default: null },
        followee: { Default: null },
        dissolve_status: { Locked: null },
      },
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
    ).toBe(manager.convertDaysToSeconds(MINIMUM_DISSOLVE_DELAY_DAYS));
  });

  it("should set maximum delay when variable exceeds maximum", async () => {
    let aboveMaximum = MAX_DISSOLVE_DELAY_DAYS + MINIMUM_DISSOLVE_DELAY_DAYS;
    await manager.modifyNode(node.id, [{ DelayDays: aboveMaximum }], [], []);

    await manager.advanceBlocksAndTimeMinutes(3);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS));
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
