import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MAX_DISSOLVE_DELAY_DAYS,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
} from "../setup/constants.ts";

describe("Stake", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    node = await manager.stakeNeuron(AMOUNT_TO_STAKE, {
      dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
      followee: { FolloweeId: MOCK_FOLLOWEE_TO_SET },
      dissolve_status: { Locked: null },
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

    await manager.modifyNode(
      node.id,
      [{ DelayDays: MAX_DISSOLVE_DELAY_DAYS }],
      [],
      []
    );
    await manager.advanceBlocksAndTimeMinutes(3);
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

    await manager.modifyNode(
      node.id,
      [],
      [{ FolloweeId: MOCK_FOLLOWEE_TO_SET_2 }],
      []
    );
    await manager.advanceBlocksAndTimeMinutes(3);
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

  it("should update dissolving", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Locked: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );

    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
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

    await manager.modifyNode(node.id, [], [], [{ Locked: null }]);
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
    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBeGreaterThan(0n);

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTimeDays(3);
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

    await manager.modifyNode(
      node.id,
      [{ DelayDays: MAX_DISSOLVE_DELAY_DAYS }],
      [],
      [{ Locked: null }]
    );
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
    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBeGreaterThan(0n);

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTimeDays(5);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(0n);

    await manager.deleteNode(node.id);
    await expect(manager.getNode(node.id)).rejects.toThrow();
  });
});
