import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nnsvector/declarations/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
} from "../setup/constants.ts";

describe("Message", () => {
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
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should throw error when updating dissolving", async () => {
    await manager.stopNnsCanister();
    await manager.advanceBlocksAndTimeMinutes(3);

    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Dissolving: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    ); // should still be locked

    // should be network error in log
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Err" in log)
          return (
            log.Err.msg === "Canister rrkah-fqaaa-aaaaa-aaaaq-cai is stopped"
          );
      })
    ).toBeTruthy();

    // start dissolving should not be there
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "start_dissolving";
      })
    ).toBeFalsy();
  });

  it("should update dissolving successfully ", async () => {
    await manager.startNnsCanister();

    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_status
    ).toEqual({
      Dissolving: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    ); // should be dissolving now
    // start dissolving should now be there
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "start_dissolving";
      })
    ).toBeTruthy();
  });

  it("should throw error when updating followees", async () => {
    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET);
    }
    await manager.stopNnsCanister();
    await manager.advanceBlocksAndTimeMinutes(3);
    await manager.modifyNode(
      node.id,
      [],
      [{ FolloweeId: MOCK_FOLLOWEE_TO_SET_2 }],
      []
    );
    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual(
      { FolloweeId: MOCK_FOLLOWEE_TO_SET_2 } // should have new
    );
    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET); // should still be old
    }

    // should be network error in log
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Err" in log)
          return (
            log.Err.msg === "Canister rrkah-fqaaa-aaaaa-aaaaq-cai is stopped"
          );
      })
    ).toBeTruthy();

    // update followees should not be there
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "update_followees";
      })
    ).toBeFalsy();
  });

  it("should update followee successfully ", async () => {
    await manager.startNnsCanister();

    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    for (let followee of node.custom[0].devefi_jes1_icpneuron.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET_2);
    }
    expect(node.custom[0].devefi_jes1_icpneuron.cache.followees).toHaveLength(
      3
    );

    // update followees should now be there
    expect(
      node.custom[0].devefi_jes1_icpneuron.log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "update_followees";
      })
    ).toBeTruthy();
  });
});
