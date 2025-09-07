import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import {
  AMOUNT_TO_STAKE,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
  MOCK_HOTKEY_TO_SET,
  MOCK_HOTKEY_TO_SET_2,
  MAX_DISSOLVE_DELAY_DAYS,
} from "../setup/constants.ts";

describe("Refresh", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE,
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { Default: null },
        followee: { Default: null },
        dissolve_status: { Locked: null },
        hotkey: { None: null },
        visibility: { Private: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should refesh neuron after 12 hours when no config changes ", async () => {
    const oldDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    await manager.advanceBlocksAndTimeHours(1); // passes 6 hours
    await manager.advanceBlocksAndTimeMinutes(3); // passes 30 minutes lets things process

    node = await manager.getNode(node.id);
    const newDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    expect(oldDoneTimestamp).toEqual(newDoneTimestamp);

    await manager.advanceBlocksAndTimeHours(1); // pass another 6 hours
    node = await manager.getNode(node.id);

    const latestDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    if ("Done" in latestDoneTimestamp) {
      // make sure it has changed and updated
      expect(latestDoneTimestamp).not.toEqual(oldDoneTimestamp);

      const done = manager.convertNanosToMillis(latestDoneTimestamp.Done);
      const now = await manager.getNow();

      // Ensure `now` is not earlier than `done`
      if (now < done) {
        throw new Error(
          `Test failed: 'now' (${now}) is earlier than 'done' (${done})`
        );
      }
      // Check if the difference is within the last hour (3600000 milliseconds in an hour)
      const thirtyMinutesInMillis = 1800000n; // 30 minutes in milliseconds
      const isWithinLastHalfHour = now - done <= thirtyMinutesInMillis;
      expect(isWithinLastHalfHour).toBe(true);
    } else {
      throw new Error(
        "'Done' state not found; 'updating' likely in 'Calling' state."
      );
    }
  });

  it("should refesh neuron after 3 minutes when config changes", async () => {
    const oldDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    await manager.modifyNode(node.id, {
      updateFollowee: { FolloweeId: MOCK_FOLLOWEE_TO_SET_2 },
    });

    await manager.advanceBlocksAndTimeMinutes(1);
    node = await manager.getNode(node.id);

    const newDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    expect(newDoneTimestamp).not.toEqual(oldDoneTimestamp);

    if ("Done" in newDoneTimestamp) {
      const done = manager.convertNanosToMillis(newDoneTimestamp.Done);
      const now = await manager.getNow();

      // Ensure `now` is not earlier than `done`
      if (now < done) {
        throw new Error(
          `Test failed: 'now' (${now}) is earlier than 'done' (${done})`
        );
      }

      const thirtyMinutesInMillis = 1800000n; // 30 minutes in milliseconds
      const isWithinLastHalfHour = now - done <= thirtyMinutesInMillis;
      expect(isWithinLastHalfHour).toBe(true);
    } else {
      throw new Error(
        "'Done' state not found; 'updating' likely in 'Calling' state."
      );
    }
    await manager.advanceBlocksAndTimeMinutes(3);
    await manager.advanceBlocksAndTimeHours(1);
    node = await manager.getNode(node.id);

    const latestDoneTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // it should have not updated again
    expect(latestDoneTimestamp).toEqual(newDoneTimestamp);
  });

  it("should refresh neuron once after hotkey changes and not constantly refresh", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Change hotkey
    await manager.modifyNode(node.id, {
      updateHotkey: { HotkeyId: MOCK_HOTKEY_TO_SET },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify hotkey was updated in cache
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(1);
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys[0]).toEqual(
      MOCK_HOTKEY_TO_SET
    );

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(6);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should refresh neuron once after visibility changes and not constantly refresh", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Change visibility
    await manager.modifyNode(node.id, {
      updateVisibility: { Public: null },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify visibility was updated in cache
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(2);

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(6);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should refresh neuron once after dissolve delay changes and not constantly refresh", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Change dissolve delay
    await manager.modifyNode(node.id, {
      updateDelay: { DelayDays: MAX_DISSOLVE_DELAY_DAYS },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify dissolve delay was updated in cache
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS));

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(6);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should refresh neuron once after dissolve status changes and not constantly refresh", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Change dissolve status
    await manager.modifyNode(node.id, {
      updateDissolving: { Dissolving: null },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify dissolve status was updated in cache
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(6);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should refresh neuron once after multiple config changes and not constantly refresh", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Make multiple config changes at once
    await manager.modifyNode(node.id, {
      updateHotkey: { HotkeyId: MOCK_HOTKEY_TO_SET_2 },
      updateVisibility: { Private: null },
      updateFollowee: { FolloweeId: MOCK_FOLLOWEE_TO_SET },
    });

    await manager.advanceBlocksAndTimeMinutes(6);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify all changes were applied
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys[0]).toEqual(
      MOCK_HOTKEY_TO_SET_2
    );
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(1);
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(3);

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(8);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should clear followees and refresh once without constant refreshing", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Clear followees
    await manager.modifyNode(node.id, {
      updateFollowee: { None: null },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify followees were cleared
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(0);

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(8);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });

  it("should handle clearing hotkey and refresh once without constant refreshing", async () => {
    const initialTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Clear hotkey
    await manager.modifyNode(node.id, {
      updateHotkey: { None: null },
    });

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    const firstRefreshTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should have triggered a refresh
    expect(firstRefreshTimestamp).not.toEqual(initialTimestamp);

    // Verify hotkey was cleared
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(0);

    // Wait additional time and verify no additional refresh
    await manager.advanceBlocksAndTimeMinutes(8);
    node = await manager.getNode(node.id);

    const laterTimestamp =
      node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // Should not have refreshed again
    expect(laterTimestamp).toEqual(firstRefreshTimestamp);
  });
});
