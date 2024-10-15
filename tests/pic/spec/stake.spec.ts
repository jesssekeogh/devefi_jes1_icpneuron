import { Setup } from "../setup/setup.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";

describe("Stake", () => {
  let setup: Setup;
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
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
    let expectedTransactionFees = 20_000n;

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
    expect(node.custom.nns_neuron.cache.followees[0][1].followees[0].id).toBe(
      followeeToSet
    );
    expect(node.custom.nns_neuron.cache.followees[1][1].followees[0].id).toBe(
      followeeToSet
    );
    expect(node.custom.nns_neuron.cache.followees[2][1].followees[0].id).toBe(
      followeeToSet
    );

    // modify to a new followee and expect it to change
    let newFollowee: bigint = 8571487073262291504n;

    await setup.modifyNode(node.id, [newFollowee], []);
    await setup.advanceBlocksAndTime(3);
    node = await setup.getNode(node.id);

    expect(node.custom.nns_neuron.variables.update_followee).toBe(newFollowee);
    expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);
    expect(node.custom.nns_neuron.cache.followees[0][1].followees[0].id).toBe(
      newFollowee
    );
    expect(node.custom.nns_neuron.cache.followees[1][1].followees[0].id).toBe(
      newFollowee
    );
    expect(node.custom.nns_neuron.cache.followees[2][1].followees[0].id).toBe(
      newFollowee
    );
  });

  it("should update dissolving", async () => {
    expect(node.custom.nns_neuron.variables.update_dissolving).toBeFalsy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(setup.getNeuronStates().locked);
    
    await setup.modifyNode(node.id, [], [true]);
    await setup.advanceBlocksAndTime(3);
    node = await setup.getNode(node.id);

    expect(node.custom.nns_neuron.variables).toBeTruthy();
    expect(node.custom.nns_neuron.cache.state[0]).toBe(setup.getNeuronStates().dissolving);
  });

  // TODO Increase Stake and check refresh
  // TODO Disburse a dissolved main neuron
  // TODO multiple neurons
});
