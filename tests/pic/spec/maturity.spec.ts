import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import { Maturity } from "../setup/maturity.ts";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY_DAYS,
} from "../setup/constants.ts";

describe("Maturity", () => {
  let manager: Manager;
  let maturity: Maturity;
  let node: NodeShared;
  let maturityFollowee: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    maturityFollowee = await maturity.createNeuron();

    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE,
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
        followee: { FolloweeId: maturityFollowee },
        dissolve_status: { Locked: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should accrue maturity", async () => {
    await maturity.createMotionProposal(maturityFollowee);

    await manager.advanceBlocksAndTimeDays(5);
    await manager.advanceBlocksAndTimeHours(3);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.maturity_e8s_equivalent[0]
    ).toBeGreaterThan(0n);
  });

  it("should spawn maturity", async () => {
    await manager.advanceBlocksAndTimeDays(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
    ).toBeGreaterThan(0);
    expect(node.custom[0].devefi_jes1_icpneuron.internals.local_idx).toBe(1);
  });

  it("should claim maturity", async () => {
    let oldBalance = await manager.getMyBalances();

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
    ).toBe(0);
    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });

  it("should spawn and claim maturity again", async () => {
    await maturity.createMotionProposal(maturityFollowee);

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
    ).toBeGreaterThan(0);
    expect(node.custom[0].devefi_jes1_icpneuron.internals.local_idx).toBe(2);

    let oldBalance = await manager.getMyBalances();

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
    ).toBe(0);

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });
});
