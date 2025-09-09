import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import { Maturity } from "../setup/maturity.ts";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MAX_DISSOLVE_DELAY_DAYS,
  MOCK_HOTKEY_TO_SET,
  SPLIT_AMOUNT,
  ICP_TRANSACTION_FEE,
  STAKE_MULTIPLIER_FOR_SPLIT,
} from "../setup/constants.ts";
import { createIdentity } from "@dfinity/pic";

describe("Split", () => {
  let manager: Manager;
  let maturity: Maturity;
  let node: NodeShared;
  let maturityFollowee: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    maturityFollowee = await maturity.createNeuron();

    // Create and stake a neuron with sufficient stake to split
    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT, // Stake more than usual to have enough to split
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
        followee: { FolloweeId: maturityFollowee },
        dissolve_status: { Locked: null },
        hotkey: { HotkeyId: MOCK_HOTKEY_TO_SET },
        visibility: { Private: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should have initial neuron with correct setup", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(
      AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT - EXPECTED_TRANSACTION_FEES
    );

    // Verify neuron_cache contains the main neuron
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(1);

    // Verify main neuron in cache matches the cache
    const mainNeuronInCache =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache[0];
    expect(mainNeuronInCache.neuron_id[0]).toBe(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    );
    expect(mainNeuronInCache.cached_neuron_stake_e8s[0]).toBe(
      AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT - EXPECTED_TRANSACTION_FEES
    );

    // Verify initial variables
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_delay
    ).toEqual({ DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      FolloweeId: maturityFollowee,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      HotkeyId: MOCK_HOTKEY_TO_SET,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Private: null,
    });
  });

  it("should not split neuron below minimum stake", async () => {
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    // Perform the split
    const splitResult = await manager.getVector().icpneuron_split({
      vid: node.id,
      caller_subaccount: [], // null
      amount_e8s: SPLIT_AMOUNT - 10_0000_0000n, // Try to split just below minimum
      neuronId: mainNeuronId,
    });

    expect("err" in splitResult).toBe(true);
    expect(splitResult).toEqual({
      err: "Amount to split must be at least 2_000_000_000 e8s",
    });
  });

  it("should not split neuron if caller is not a controller", async () => {
    const pylon = manager.getVector();

    pylon.setIdentity(createIdentity("superSecretBobPassword"));

    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    // Perform the split
    const splitResult = await pylon.icpneuron_split({
      vid: node.id,
      caller_subaccount: [], // null
      amount_e8s: SPLIT_AMOUNT,
      neuronId: mainNeuronId,
    });

    expect("err" in splitResult).toBe(true);
    expect(splitResult).toEqual({ err: "Not a controller" });

    // set it back
    pylon.setIdentity(createIdentity("superSecretAlicePassword"));
  });

  it("should not split neuron with invalid neuron ID", async () => {
    // Use a fake neuron ID that doesn't exist
    const fakeNeuronId = 999999999999999999n;

    // Perform the split with invalid neuron ID
    const splitResult = await manager.getVector().icpneuron_split({
      vid: node.id,
      caller_subaccount: [], // null
      amount_e8s: SPLIT_AMOUNT,
      neuronId: fakeNeuronId,
    });

    expect("err" in splitResult).toBe(true);
    expect(splitResult).toEqual({ err: `Neuron ID 999_999_999_999_999_999 not found in node's neuron cache` });
  });

  it("should successfully split neuron", async () => {
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];
    const initialStake =
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0];

    // Perform the split
    const splitResult = await manager.getVector().icpneuron_split({
      vid: node.id,
      caller_subaccount: [], // null
      amount_e8s: SPLIT_AMOUNT,
      neuronId: mainNeuronId,
    });

    expect("ok" in splitResult).toBe(true);

    // Advance time to allow processing
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    // Verify the main neuron stake is reduced
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(initialStake - SPLIT_AMOUNT);

    // Verify we now have 2 neurons total (main + 1 split)
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(2);

    // Find the split neuron (not the main neuron)
    const splitNeuron = node.custom[0].devefi_jes1_icpneuron.neuron_cache.find(
      (neuron) => neuron.neuron_id[0] !== mainNeuronId
    );
    expect(splitNeuron).toBeDefined();

    // Verify split neuron has correct stake
    expect(splitNeuron.cached_neuron_stake_e8s[0]).toBe(
      SPLIT_AMOUNT - ICP_TRANSACTION_FEE
    );

    // Verify split neuron has same parameters as main neuron
    expect(splitNeuron.dissolve_delay_seconds[0]).toBe(
      manager.convertDaysToSeconds(MINIMUM_DISSOLVE_DELAY_DAYS)
    );
    expect(splitNeuron.followees).toHaveLength(3); // Same followee structure
    expect(splitNeuron.hot_keys).toHaveLength(1);
    expect(splitNeuron.hot_keys[0]).toEqual(MOCK_HOTKEY_TO_SET);
    expect(splitNeuron.visibility[0]).toBe(1); // Private = 1
    expect(splitNeuron.state[0]).toBe(manager.getNeuronStates().locked);

    // Verify main neuron is also updated in neuron_cache
    const mainNeuronInCache =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.find(
        (neuron) => neuron.neuron_id[0] === mainNeuronId
      );
    expect(mainNeuronInCache).toBeDefined();
    expect(mainNeuronInCache.cached_neuron_stake_e8s[0]).toBe(
      initialStake - SPLIT_AMOUNT
    );
  });

  it("should handle multiple splits", async () => {
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];
    const initialStake =
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0];

    const numberOfSplits = 3; // Create 3 additional neurons for total of 5 (1 main + 1 previous split + 3 new splits)

    // Perform multiple splits in a loop
    for (let i = 0; i < numberOfSplits; i++) {
      const splitResult = await manager.getVector().icpneuron_split({
        vid: node.id,
        caller_subaccount: [],
        amount_e8s: SPLIT_AMOUNT,
        neuronId: mainNeuronId,
      });

      expect("ok" in splitResult).toBe(true);
    }

    // Advance time after each split to allow processing
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    // Verify we now have 5 neurons total (main + 4 splits)
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(5);

    // Verify main neuron stake is reduced by all splits
    const expectedMainStake =
      initialStake - BigInt(numberOfSplits) * SPLIT_AMOUNT;
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(expectedMainStake);

    // Verify main neuron in cache
    const mainNeuronInCache =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.find(
        (neuron) => neuron.neuron_id[0] === mainNeuronId
      );
    expect(mainNeuronInCache.cached_neuron_stake_e8s[0]).toBe(
      expectedMainStake
    );

    // Verify all split neurons have correct stakes 
    const splitNeurons =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.filter(
        (neuron) => neuron.neuron_id[0] !== mainNeuronId
      );
    expect(splitNeurons).toHaveLength(numberOfSplits + 1); // +1 for previous split
    splitNeurons.forEach((splitNeuron) => {
      expect(splitNeuron.cached_neuron_stake_e8s[0]).toBe(
        SPLIT_AMOUNT - ICP_TRANSACTION_FEE
      );
    });
  });

  it("should respect 3-minute timeout between neuron updates", async () => {
    // Store initial state of all neurons to track which ones get updated
    const initialNeuronStates =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.map((neuron) => ({
        neuron_id: neuron.neuron_id[0],
        dissolve_delay_seconds: neuron.dissolve_delay_seconds[0],
        followees_length: neuron.followees.length,
        hot_keys_length: neuron.hot_keys.length,
        visibility: neuron.visibility[0],
      }));

    expect(initialNeuronStates).toHaveLength(5); // Should have 5 neurons from previous tests

    // Modify node variables
    await manager.modifyNode(node.id, {
      updateDelay: { DelayDays: MAX_DISSOLVE_DELAY_DAYS },
      updateFollowee: { None: null },
      updateHotkey: { None: null },
      updateVisibility: { Public: null },
    });

    // Wait only 6 minutes - with 3-minute intervals, only 1-2 neurons should be updated
    await manager.advanceBlocksAndTimeMinutes(6);

    node = await manager.getNode(node.id);

    // Verify variables are updated
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_delay
    ).toEqual({ DelayDays: MAX_DISSOLVE_DELAY_DAYS });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Public: null,
    });

    // Count how many neurons have been updated vs remain unchanged
    let updatedNeurons = 0;
    let unchangedNeurons = 0;

    node.custom[0].devefi_jes1_icpneuron.neuron_cache.forEach(
      (neuron, index) => {
        const initial = initialNeuronStates[index];
        const isUpdated =
          neuron.dissolve_delay_seconds[0] ===
            manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS) &&
          neuron.followees.length === 0 &&
          neuron.hot_keys.length === 0 &&
          neuron.visibility[0] === 2; // Public = 2

        if (isUpdated) {
          updatedNeurons++;
        } else {
          unchangedNeurons++;
          // Verify unchanged neurons still have their original values
          expect(neuron.dissolve_delay_seconds[0]).toBe(
            initial.dissolve_delay_seconds
          );
          expect(neuron.followees.length).toBe(initial.followees_length);
          expect(neuron.hot_keys.length).toBe(initial.hot_keys_length);
          expect(neuron.visibility[0]).toBe(initial.visibility);
        }
      }
    );

    // With 6 minutes and 3-minute intervals, we should have updated 1-2 neurons
    // (0-3min: 1st neuron, 3-6min: 2nd neuron potentially)
    expect(updatedNeurons).toBeGreaterThanOrEqual(1);
    expect(updatedNeurons).toBeLessThanOrEqual(2);
    expect(unchangedNeurons).toBeGreaterThanOrEqual(3);

    // Now wait enough time for ALL neurons to be updated (5 neurons × 3 minutes = 15 minutes total)
    // We already waited 6 minutes, so wait another 12 minutes to ensure all are updated
    await manager.advanceBlocksAndTimeMinutes(12);

    node = await manager.getNode(node.id);

    // Verify ALL neurons are now updated with the new values
    let allUpdatedNeurons = 0;
    let stillUnchangedNeurons = 0;

    node.custom[0].devefi_jes1_icpneuron.neuron_cache.forEach((neuron) => {
      const isFullyUpdated =
        neuron.dissolve_delay_seconds[0] === 
          manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS) &&
        neuron.followees.length === 0 &&
        neuron.hot_keys.length === 0 &&
        neuron.visibility[0] === 2; // Public = 2

      if (isFullyUpdated) {
        allUpdatedNeurons++;
      } else {
        stillUnchangedNeurons++;
      }
    });

    // After 18 total minutes (6 + 12), ALL neurons should be updated
    expect(allUpdatedNeurons).toBe(5); // All 5 neurons should be updated
    expect(stillUnchangedNeurons).toBe(0); // No neurons should remain unchanged
  });

  it("should update all neurons when variables are modified", async () => {
    // Modify node variables (if they weren't already modified in previous test)
    await manager.modifyNode(node.id, {
      updateDelay: { DelayDays: MAX_DISSOLVE_DELAY_DAYS },
      updateFollowee: { None: null },
      updateHotkey: { None: null },
      updateVisibility: { Public: null },
    });

    await manager.advanceBlocksAndTimeMinutes(16);

    node = await manager.getNode(node.id);

    // Verify main neuron is updated
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS));
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      0
    );
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(0);
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(2); // Public = 2

    // Verify ALL neurons in neuron_cache are updated (including main neuron)
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(5); // Should now have 5 neurons

    node.custom[0].devefi_jes1_icpneuron.neuron_cache.forEach((neuron) => {
      expect(neuron.dissolve_delay_seconds[0]).toBe(
        manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS)
      );
      expect(neuron.followees).toHaveLength(0);
      expect(neuron.hot_keys).toHaveLength(0);
      expect(neuron.visibility[0]).toBe(2); // Public = 2
    });

    // Verify variables are updated
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_delay
    ).toEqual({ DelayDays: MAX_DISSOLVE_DELAY_DAYS });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Public: null,
    });
  });

  it("should handle maturity disbursements across all split neurons", async () => {
    // Set up for maturity accrual
    await manager.modifyNode(node.id, {
      updateFollowee: { FolloweeId: maturityFollowee },
    });

    await manager.advanceBlocksAndTimeMinutes(16);

    // Create a motion proposal to generate maturity rewards
    await maturity.createMotionProposal(maturityFollowee);

    // Advance enough time to trigger maturity spawning (skip accrual verification)
    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);

    // Verify maturity disbursements are in progress across all neurons
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache
        .maturity_disbursements_in_progress[0].length
    ).toBeGreaterThan(0);

    // Verify all split neurons in neuron_cache also have maturity disbursements
    let totalDisbursementsInProgress = 0;
    node.custom[0].devefi_jes1_icpneuron.neuron_cache.forEach((neuron) => {
      expect(
        neuron.maturity_disbursements_in_progress[0].length
      ).toBeGreaterThan(0);
      totalDisbursementsInProgress +=
        neuron.maturity_disbursements_in_progress[0].length;
    });

    // Get initial balance to verify disbursement
    let oldBalance = await manager.getMyBalances();

    // Advance time to complete maturity disbursement
    await manager.advanceBlocksAndTimeDays(8);
    await manager.advanceBlocksAndTimeMinutes(3);

    node = await manager.getNode(node.id);

    // Verify all disbursements are completed across all neurons
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache
        .maturity_disbursements_in_progress[0].length
    ).toBe(0);

    node.custom[0].devefi_jes1_icpneuron.neuron_cache.forEach((neuron) => {
      expect(neuron.maturity_disbursements_in_progress[0].length).toBe(0);
    });

    // Verify balance increased due to maturity disbursements
    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
});
