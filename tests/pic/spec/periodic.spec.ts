import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";

describe("Periodic", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE,
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
        followee: { FolloweeId: MOCK_FOLLOWEE_TO_SET },
        dissolve_status: { Locked: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should refresh neurons voting power after 90 days", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.potential_voting_power[0]
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.deciding_voting_power[0]
    ).toBeDefined();

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache
        .voting_power_refreshed_timestamp_seconds[0]
    ).toBe(
      node.custom[0].devefi_jes1_icpneuron.cache.created_timestamp_seconds[0]
    );

    await manager.advanceTime(8208000); // 95 days
    await manager.advanceBlocks(100);

    node = await manager.getNode(node.id);

    // Get the timestamps for easier reference
    const refreshedTimestamp =
      node.custom[0].devefi_jes1_icpneuron.cache
        .voting_power_refreshed_timestamp_seconds[0];
    const createdTimestamp =
      node.custom[0].devefi_jes1_icpneuron.cache.created_timestamp_seconds[0];

    // Check that the refresh timestamp is NOT the same as creation timestamp
    expect(refreshedTimestamp).not.toBe(createdTimestamp);

    // Check that the refresh timestamp is recent (within a reasonable range of expected time)
    expect(refreshedTimestamp).toBeGreaterThanOrEqual(createdTimestamp);

    // should have successful refresh_voting_power operation in log
    expect(
        node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
          if ("Ok" in log)
            return log.Ok.operation === "refresh_voting_power";
          return false;
        })
      ).toBeTruthy();
  });
});
