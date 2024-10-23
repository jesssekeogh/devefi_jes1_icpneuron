import { Setup } from "../setup/setup.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";

describe("Stake", () => {
  let setup: Setup;
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
  let expectedTransactionFees: bigint = 20_000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let followeeToSet: bigint = 6914974521667616512n;
  let isDissolving: boolean = false;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
    node = await setup.stakeNeuron(10_0000_0000n, {
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

  it("should set neuron dissolve delay", async () => {
    expect(node.custom.nns_neuron.cache.dissolve_delay_seconds[0]).toBe(
      dissolveDelayToSet
    );
    // TODO add a feature to increase?
  });

  it("should update followee", async () => {
    expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);

    for (let followee of node.custom.nns_neuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(followeeToSet);
    }

    // modify to a new followee and expect it to change
    let newFollowee: bigint = 8571487073262291504n;

    await setup.modifyNode(node.id, [], [newFollowee], []);
    await setup.advanceBlocksAndTime(3);
    node = await setup.getNode(node.id);

    expect(node.custom.nns_neuron.variables.update_followee).toBe(newFollowee);
    expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);

    for (let followee of node.custom.nns_neuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(newFollowee);
    }
  });

  it("should update dissolving", async () => {
    expect(node.custom.nns_neuron.variables.update_dissolving).toBeFalsy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      setup.getNeuronStates().locked
    );

    await setup.modifyNode(node.id, [], [], [true]);
    await setup.advanceBlocksAndTime(3);
    node = await setup.getNode(node.id);

    expect(node.custom.nns_neuron.variables).toBeTruthy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(
      setup.getNeuronStates().dissolving
    );

    // TODO set back to false and expect
  });

  it("should increase stake", async () => {
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      amountToStake - expectedTransactionFees
    );
    let currentStake = amountToStake - expectedTransactionFees;

    let sends = 3;
    for (let i = 0; i < sends; i++) {
      await setup.sendIcp(setup.getNodeSourceAccount(node), amountToStake);
      await setup.advanceBlocksAndTime(1);
    }

    await setup.advanceBlocksAndTime(3);
    node = await setup.getNode(node.id);
    expect(node.custom.nns_neuron.internals.refresh_idx).toHaveLength(0);
    expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
      currentStake + (amountToStake - expectedTransactionFees) * BigInt(sends)
    );
  });

  // TODO disburse a dissolved neuron
  // TODO multiple neurons
});
