import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MAX_DISSOLVE_DELAY,
  MINIMUM_DISSOLVE_DELAY,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
} from "../setup/constants.ts";

describe("Stake", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    node = await manager.stakeNeuron(AMOUNT_TO_STAKE, {
      dissolveDelay: MINIMUM_DISSOLVE_DELAY,
      followee: MOCK_FOLLOWEE_TO_SET,
      dissolving: false,
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake neuron", async () => {
    expect(node.custom[0].nns.cache.neuron_id[0]).toBeDefined();
    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(
      AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES
    );
  });

  it("should update dissolve delay", async () => {
    expect(node.custom[0].nns.cache.dissolve_delay_seconds[0]).toBe(
      MINIMUM_DISSOLVE_DELAY
    );

    await manager.modifyNode(node.id, [MAX_DISSOLVE_DELAY], [], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);
    expect(node.custom[0].nns.cache.dissolve_delay_seconds[0]).toBe(
      MAX_DISSOLVE_DELAY
    );

    let failDelay = MAX_DISSOLVE_DELAY + MINIMUM_DISSOLVE_DELAY;
    await manager.modifyNode(node.id, [failDelay], [], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);
    expect(node.custom[0].nns.cache.dissolve_delay_seconds[0]).toBe(
      MAX_DISSOLVE_DELAY
    );
  });

  it("should update followee", async () => {
    expect(node.custom[0].nns.cache.followees).toHaveLength(3);

    for (let followee of node.custom[0].nns.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET);
    }

    // modify to a new followee and expect it to change

    await manager.modifyNode(node.id, [], [MOCK_FOLLOWEE_TO_SET_2], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.variables.update_followee).toBe(
      MOCK_FOLLOWEE_TO_SET_2
    );
    expect(node.custom[0].nns.cache.followees).toHaveLength(3);

    for (let followee of node.custom[0].nns.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET_2);
    }
  });

  it("should update dissolving", async () => {
    expect(node.custom[0].nns.variables.update_dissolving).toBeFalsy();
    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );

    await manager.modifyNode(node.id, [], [], [true]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.variables.update_dissolving).toBeTruthy();
    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    await manager.modifyNode(node.id, [], [], [false]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.variables.update_dissolving).toBeFalsy();
    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );
  });

  it("should increase stake", async () => {
    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(
      AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES
    );
    let currentStake = AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES;

    let sends = 3n;
    for (let i = 0n; i < sends; i++) {
      await manager.sendIcp(
        manager.getNodeSourceAccount(node),
        AMOUNT_TO_STAKE
      );
      await manager.advanceBlocksAndTime(1);
    }

    await manager.advanceBlocksAndTime(5);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.internals.refresh_idx).toHaveLength(0);
    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(
      currentStake + (AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES) * sends
    );
  });

  it("should disburse dissolved neuron", async () => {
    await manager.modifyNode(node.id, [], [], [true]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBeGreaterThan(
      0n
    );

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTime(10);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(0n);
  });

  it("should re-use empty neuron", async () => {
    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(0n);
    await manager.sendIcp(manager.getNodeSourceAccount(node), AMOUNT_TO_STAKE);
    await manager.advanceBlocksAndTime(3);

    await manager.modifyNode(node.id, [MAX_DISSOLVE_DELAY], [], [false]);
    await manager.advanceBlocksAndTime(5);
    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.cache.cached_neuron_stake_e8s[0]).toBe(
      AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES
    );
    expect(node.custom[0].nns.cache.dissolve_delay_seconds[0]).toBe(
      MAX_DISSOLVE_DELAY
    );
  });
});
