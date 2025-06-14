import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import { AMOUNT_TO_STAKE, MOCK_FOLLOWEE_TO_SET_2 } from "../setup/constants.ts";

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

    await manager.modifyNode(
      node.id,
      [],
      [{ FolloweeId: MOCK_FOLLOWEE_TO_SET_2 }],
      []
    );

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

    const latestDoneTimestamp = node.custom[0].devefi_jes1_icpneuron.internals.updating;

    // it should have not updated again
    expect(latestDoneTimestamp).toEqual(newDoneTimestamp);
  });
});
