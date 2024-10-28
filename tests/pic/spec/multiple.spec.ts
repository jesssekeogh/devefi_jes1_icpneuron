import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import { createIdentity } from "@hadronous/pic";
import { Setup } from "../setup/setup.ts";

describe("Multiple", () => {
  let setup: Setup;
  let manager: Manager;
  let maturity: Maturity;
  let nodes: NodeShared[];
  let amountToStake: bigint = 10_0000_0000n;
  let expectedTransactionFees: bigint = 20_000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let followeeToSet: bigint = 6914974521667616512n;
  let isDissolving: boolean = false;
  let followeeNeuronId: bigint;

  beforeAll(async () => {
    let me = createIdentity("superSecretAlicePassword");
    setup = await Setup.beforeAll();
    manager = await Manager.beforeAll(setup.getPicInstance(), me);
    maturity = Maturity.beforeAll(manager);
    followeeNeuronId = await maturity.createNeuron();

    const nodesToCreate = 3;

    let done = [];
    for (let i = 0; i < nodesToCreate; i++) {
      let node = await manager.stakeNeuron(amountToStake, {
        dissolveDelay: dissolveDelayToSet,
        followee: followeeToSet,
        dissolving: isDissolving,
      });
      done.push(node);
    }

    nodes = done;
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should stake multiple neurons", async () => {
    for (let node of nodes) {
      expect(node.custom.nns_neuron.cache.neuron_id[0]).toBeDefined();
      expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
        amountToStake - expectedTransactionFees
      );
    }
  });

  it("should update multiple neurons", async () => {
    for (let node of nodes) {
      await manager.modifyNode(node.id, [], [followeeNeuronId], []);
      await manager.advanceBlocksAndTime(3);
    }

    await manager.advanceBlocksAndTime(1);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(node.custom.nns_neuron.variables.update_followee).toBe(
        followeeNeuronId
      );
      expect(node.custom.nns_neuron.cache.followees).toHaveLength(3);

      for (let followee of node.custom.nns_neuron.cache.followees) {
        expect(followee[1].followees[0].id).toBe(followeeNeuronId);
      }
    }
  });

  it("should increase multiple neurons stake", async () => {
    let currentStake = amountToStake - expectedTransactionFees;
    let sends = 3n;

    for (let node of nodes) {
      for (let i = 0n; i < sends; i++) {
        await manager.sendIcp(
          manager.getNodeSourceAccount(node),
          amountToStake
        );
        await manager.advanceBlocksAndTime(1);
      }
    }

    await manager.advanceBlocksAndTime(3);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(node.custom.nns_neuron.internals.refresh_idx).toHaveLength(0);
      expect(node.custom.nns_neuron.cache.cached_neuron_stake_e8s[0]).toBe(
        currentStake + (amountToStake - expectedTransactionFees) * sends
      );
    }
  });

  it("should spawn maturity in multiple neurons", async () => {
    await maturity.createMotionProposal(followeeNeuronId);
    await manager.advanceTime(20160); // 2 weeks
    await manager.advanceBlocks(10);
    await manager.advanceBlocksAndTime(3);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom.nns_neuron.internals.spawning_neurons.length
      ).toBeGreaterThan(0);
      expect(node.custom.nns_neuron.internals.local_idx).toBe(1);
    }
  });

  it("should claim maturity from multiple neurons", async () => {
    let oldBalance = await manager.getMyBalances();

    await manager.advanceTime(10160); // 1 week
    await manager.advanceBlocks(10);

    await manager.advanceBlocksAndTime(5);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(node.custom.nns_neuron.internals.spawning_neurons.length).toBe(0);
    }

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
  
});
