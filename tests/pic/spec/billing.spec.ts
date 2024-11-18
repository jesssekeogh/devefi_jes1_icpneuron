import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nnsvector/declarations/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY_DAYS,
} from "../setup/constants.ts";

describe("Billing", () => {
  let manager: Manager;
  let maturity: Maturity;
  let nodes: NodeShared[];
  let maturityFollowee: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    maturityFollowee = await maturity.createNeuron();

    const nodesToCreate = 2;

    let done = [];
    for (let i = 0; i < nodesToCreate; i++) {
      let node = await manager.stakeNeuron({
        stake_amount: AMOUNT_TO_STAKE,
        billing_option: BigInt(i),
        neuron_params: {
          dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
          followee: { FolloweeId: maturityFollowee },
          dissolve_status: { Locked: null },
        },
      });
      done.push(node);
    }

    nodes = done;
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should disburse maturity for both billing options", async () => {
    let { icp_tokens, icrc_tokens } = await manager.getBillingBalances();
    let oldBalance = await manager.getMyBalances();

    expect(icp_tokens).toBe(0n);
    expect(icrc_tokens).toBe(0n);

    await maturity.createMotionProposal(maturityFollowee);

    await manager.advanceBlocksAndTimeDays(20);

    for (let node of nodes) {
      node = await manager.getNode(node.id);
      expect(node.sources[1].balance).toBe(0n); // expect maturity source to be empty
      expect(
        node.custom[0].devefi_jes1_icpneuron.internals.spawning_neurons.length
      ).toBe(0);
      expect(node.custom[0].devefi_jes1_icpneuron.internals.local_idx).toBe(1);
    }

    let newBalance = await manager.getMyBalances();
    expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens);
  });

  it("should add both fees to author account", async () => {
    let { icp_tokens, icrc_tokens } = await manager.getBillingBalances();

    expect(icp_tokens).toBeGreaterThan(0n);
    expect(icrc_tokens).toBeGreaterThan(0n);
  });
});
