import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MAX_DISSOLVE_DELAY_DAYS,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
  MOCK_HOTKEY_TO_SET,
  MOCK_HOTKEY_TO_SET_2,
} from "../setup/constants.ts";

describe("Stake", () => {
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
        hotkey: { None: null },
        visibility: { Private: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake neuron", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
  });

  it("should update dissolve delay", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MINIMUM_DISSOLVE_DELAY_DAYS));

    await manager.modifyNode(node.id, {
      updateDelay: { DelayDays: MAX_DISSOLVE_DELAY_DAYS },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS));
  });

  it("should update followee", async () => {
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      3
    );

    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET);
    }

    // modify to a new followee and expect it to change

    await manager.modifyNode(node.id, {
      updateFollowee: { FolloweeId: MOCK_FOLLOWEE_TO_SET_2 },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      FolloweeId: MOCK_FOLLOWEE_TO_SET_2,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      3
    );

    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET_2);
    }
  });

  it("should clear all followees when set to None", async () => {
    // First verify we have followees set
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      FolloweeId: MOCK_FOLLOWEE_TO_SET_2,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      3
    );

    // Verify all followees are currently set
    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees).toHaveLength(1);
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET_2);
    }

    // Modify followee to None
    await manager.modifyNode(node.id, {
      updateFollowee: { None: null },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify the variable is set to None
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      None: null,
    });

    // Verify all followees are cleared (empty arrays)
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      0
    );
  });

  it("should manage hotkey settings comprehensively", async () => {
    // Initial state - verify hotkey is None and cache is empty
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(0);

    // Set first hotkey
    await manager.modifyNode(node.id, {
      updateHotkey: { HotkeyId: MOCK_HOTKEY_TO_SET },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify first hotkey is set in variables and cache
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      HotkeyId: MOCK_HOTKEY_TO_SET,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(1);
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys[0]).toEqual(
      MOCK_HOTKEY_TO_SET
    );

    // Change to second hotkey
    await manager.modifyNode(node.id, {
      updateHotkey: { HotkeyId: MOCK_HOTKEY_TO_SET_2 },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify second hotkey replaces the first
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      HotkeyId: MOCK_HOTKEY_TO_SET_2,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(1);
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys[0]).toEqual(
      MOCK_HOTKEY_TO_SET_2
    );

    // Clear hotkey by setting to None
    await manager.modifyNode(node.id, {
      updateHotkey: { None: null },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify hotkey is cleared from both variables and cache
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.hot_keys).toHaveLength(0);
  });

  it("should manage visibility settings comprehensively", async () => {
    // Initial state - verify visibility is Private (1 in cache)
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Private: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(1);

    // Change visibility to Public
    await manager.modifyNode(node.id, {
      updateVisibility: { Public: null },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify visibility changed to Public (2 in cache)
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Public: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(2);

    // Change back to Private
    await manager.modifyNode(node.id, {
      updateVisibility: { Private: null },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    // Verify visibility changed back to Private (1 in cache)
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Private: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.visibility[0]).toBe(1);
  });

  it("should update dissolving", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Locked: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );

    await manager.modifyNode(node.id, {
      updateDissolving: { Dissolving: null },
    });
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Dissolving: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    await manager.modifyNode(node.id, {
      updateDissolving: { Locked: null },
    });
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Locked: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );
  });

  it("should increase stake", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
    let currentStake = AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES;

    let sends = 3n;
    for (let i = 0n; i < sends; i++) {
      await manager.sendIcp(
        manager.getNodeSourceAccount(node, 0),
        AMOUNT_TO_STAKE
      );
      await manager.advanceBlocksAndTimeMinutes(1);
    }

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.internals.refresh_idx
    ).toHaveLength(0);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(
      currentStake + (AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES) * sends
    );
  });

  it("should disburse dissolved neuron", async () => {
    await manager.modifyNode(node.id, {
      updateDissolving: { Dissolving: null },
    });
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBeGreaterThan(0n);

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(500);

    await manager.advanceBlocksAndTimeDays(1);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(0n);
  });

  it("should re-use empty neuron", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(0n);
    await manager.sendIcp(
      manager.getNodeSourceAccount(node, 0),
      AMOUNT_TO_STAKE
    );
    await manager.advanceBlocksAndTimeMinutes(3);

    await manager.modifyNode(node.id, {
      updateDelay: { DelayDays: MAX_DISSOLVE_DELAY_DAYS },
      updateDissolving: { Locked: null },
    });
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.dissolve_delay_seconds[0]
    ).toBe(manager.convertDaysToSeconds(MAX_DISSOLVE_DELAY_DAYS));
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );
  });

  it("should delete node with an empty neuron", async () => {
    await manager.modifyNode(node.id, {
      updateDissolving: { Dissolving: null },
    });
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBeGreaterThan(0n);

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(500);

    await manager.advanceBlocksAndTimeDays(1);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(0n);

    await manager.deleteNode(node.id);
    await expect(manager.getNode(node.id)).rejects.toThrow();
  });
});
