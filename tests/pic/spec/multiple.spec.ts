import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MINIMUM_DISSOLVE_DELAY,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";

describe("Multiple", () => {
  let manager: Manager;
  let maturity: Maturity;
  let nodes: NodeShared[];
  let maturityFollowee: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    maturityFollowee = await maturity.createNeuron();

    const nodesToCreate = 3;

    let done = [];
    for (let i = 0; i < nodesToCreate; i++) {
      let node = await manager.stakeNeuron(AMOUNT_TO_STAKE, {
        dissolveDelay: MINIMUM_DISSOLVE_DELAY,
        followee: MOCK_FOLLOWEE_TO_SET,
        dissolving: { KeepLocked: null },
      });
      done.push(node);
    }

    nodes = done;
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake multiple neurons", async () => {
    for (let node of nodes) {
      expect(
        node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
      ).toBeDefined();
      expect(
        node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
      ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
    }
  });

  it("should update multiple neurons", async () => {
    for (let node of nodes) {
      await manager.modifyNode(node.id, [], [maturityFollowee], []);
      await manager.advanceBlocksAndTimeMinutes(3);
    }

    await manager.advanceBlocksAndTimeMinutes(1);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_icpneuron.variables.update_followee
      ).toBe(maturityFollowee);
      expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
        3
      );

      for (let followee of node.custom[0].devefi_jes1_icpneuron.cache
        .followees) {
        expect(followee[1].followees[0].id).toBe(maturityFollowee);
      }
    }
  });

  it("should increase multiple neurons stake", async () => {
    let currentStake = AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES;
    let sends = 3n;

    for (let node of nodes) {
      for (let i = 0n; i < sends; i++) {
        await manager.sendIcp(
          manager.getNodeSourceAccount(node, 0),
          AMOUNT_TO_STAKE
        );
        await manager.advanceBlocksAndTimeMinutes(1);
      }
    }

    await manager.advanceBlocksAndTimeMinutes(5);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_icpneuron.internals.refresh_idx
      ).toHaveLength(0);
      expect(
        node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
      ).toBe(
        currentStake + (AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES) * sends
      );
    }
  });

  it("should spawn maturity in multiple neurons", async () => {
    await maturity.createMotionProposal(maturityFollowee);
    await manager.advanceTime(20160); // 2 weeks
    await manager.advanceBlocks(10);
    await manager.advanceBlocksAndTimeDays(3);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
      ).toBeGreaterThan(0);
      expect(node.custom[0].devefi_jes1_icpneuron.internals.local_idx).toBe(1);
    }
  });

  it("should claim maturity from multiple neurons", async () => {
    let oldBalance = await manager.getMyBalances();

    await manager.advanceTime(10160); // 1 week
    await manager.advanceBlocks(10);

    await manager.advanceBlocksAndTimeDays(5);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
      ).toBe(0);
    }

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
});
