import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { createIdentity } from "@hadronous/pic";
import { Setup } from "../setup/setup.ts";

describe("Stake", () => {
  let setup: Setup;
  let manager: Manager;
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
  let expectedTransactionFees: bigint = 20_000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let followeeToSet: bigint = 6914974521667616512n;
  let isDissolving: boolean = false;

  beforeAll(async () => {
    let me = createIdentity("superSecretAlicePassword");
    setup = await Setup.beforeAll();
    manager = await Manager.beforeAll(setup.getPicInstance(), me);

    node = await manager.stakeNeuron(amountToStake, {
      dissolveDelay: dissolveDelayToSet,
      followee: followeeToSet,
      dissolving: isDissolving,
    });
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should stake neuron", async () => {
    expect(node.custom.nns_neuron.cache.neuron_id[0]).toBeDefined();
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      amountToStake - expectedTransactionFees
    );
  });

  it("update dissolve delay", async () => {
    expect(node.custom.nns_neuron.cache.dissolve_delay_seconds[0]).toBe(
      dissolveDelayToSet
    );

    let oneYearSeconds = ((4n * 365n + 1n) * (24n * 60n * 60n)) / 4n;
    let maxDelay = 8n * oneYearSeconds;
    await manager.modifyNode(node.id, [maxDelay], [], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);
    expect(node.custom.nns_neuron.cache.dissolve_delay_seconds[0]).toBe(
      maxDelay
    );

    let failDelay = maxDelay + dissolveDelayToSet;
    await manager.modifyNode(node.id, [failDelay], [], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);
    expect(node.custom.nns_neuron.cache.dissolve_delay_seconds[0]).toBe(
      maxDelay
    );
  });

  it("should update followee", async () => {
    expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);

    for (let followee of node.custom.nns_neuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(followeeToSet);
    }

    // modify to a new followee and expect it to change
    let newFollowee: bigint = 8571487073262291504n;

    await manager.modifyNode(node.id, [], [newFollowee], []);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.variables.update_followee).toBe(newFollowee);
    expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);

    for (let followee of node.custom.nns_neuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(newFollowee);
    }
  });

  it("should update dissolving", async () => {
    expect(node.custom.nns_neuron.variables.update_dissolving).toBeFalsy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );

    await manager.modifyNode(node.id, [], [], [true]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.variables.update_dissolving).toBeTruthy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    await manager.modifyNode(node.id, [], [], [false]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.variables.update_dissolving).toBeFalsy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    );
  });

  it("should increase stake", async () => {
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      amountToStake - expectedTransactionFees
    );
    let currentStake = amountToStake - expectedTransactionFees;

    let sends = 3n;
    for (let i = 0n; i < sends; i++) {
      await manager.sendIcp(manager.getNodeSourceAccount(node), amountToStake);
      await manager.advanceBlocksAndTime(1);
    }

    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);
    expect(node.custom.nns_neuron.internals.refresh_idx).toHaveLength(0);
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      currentStake + (amountToStake - expectedTransactionFees) * sends
    );
  });

  it("should disburse dissolved neuron", async () => {
    await manager.modifyNode(node.id, [], [], [true]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    );

    expect(
      node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]
    ).toBeGreaterThan(0n);

    await manager.advanceTime(4300000); // 8 years
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTime(10);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(0n);
  });

  it("should re-use empty neuron", async () => {
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(0n);
    await manager.sendIcp(manager.getNodeSourceAccount(node), amountToStake);
    await manager.advanceBlocksAndTime(3);

    let oneYearSeconds = ((4n * 365n + 1n) * (24n * 60n * 60n)) / 4n;
    let maxDelay = 8n * oneYearSeconds;
    await manager.modifyNode(node.id, [maxDelay], [], [false]);
    await manager.advanceBlocksAndTime(3);
    node = await manager.getNode(node.id);

    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      amountToStake - expectedTransactionFees
    );
    expect(node.custom.nns_neuron.cache.dissolve_delay_seconds[0]).toBe(
      maxDelay
    );
  });
});
