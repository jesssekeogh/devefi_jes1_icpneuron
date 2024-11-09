import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
} from "../setup/constants.ts";

describe("Message", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    node = await manager.stakeNeuron(AMOUNT_TO_STAKE, {
      dissolveDelay: MINIMUM_DISSOLVE_DELAY,
      followee: MOCK_FOLLOWEE_TO_SET,
      dissolving: { KeepLocked: null },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should throw error when updating dissolving", async () => {
    await manager.stopNnsCanister();
    await manager.advanceBlocksAndTimeMinutes(3);

    await manager.modifyNode(node.id, [], [], [{ StartDissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.variables.update_dissolving).toBeTruthy();
    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().locked
    ); // should still be locked

    // should be network error in log
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Err" in log)
          return (
            log.Err.msg === "Canister rrkah-fqaaa-aaaaa-aaaaq-cai is stopped"
          );
      })
    ).toBeTruthy();

    // start dissolving should not be there
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "start_dissolving";
      })
    ).toBeFalsy();
  });

  it("should update dissolving successfully ", async () => {
    await manager.startNnsCanister();

    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    expect(node.custom[0].nns.variables.update_dissolving).toBeTruthy();
    expect(node.custom[0].nns.cache.state[0]).toBe(
      manager.getNeuronStates().dissolving
    ); // should be dissolving now
    // start dissolving should now be there
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "start_dissolving";
      })
    ).toBeTruthy();
  });

  it("should throw error when updating followees", async () => {
    for (let followee of node.custom[0].nns.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET);
    }
    await manager.stopNnsCanister();
    await manager.advanceBlocksAndTimeMinutes(3);
    await manager.modifyNode(node.id, [], [MOCK_FOLLOWEE_TO_SET_2], []);
    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);
    expect(node.custom[0].nns.variables.update_followee).toBe(
      MOCK_FOLLOWEE_TO_SET_2 // should have new
    );
    for (let followee of node.custom[0].nns.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET); // should still be old
    }

    // should be network error in log
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Err" in log)
          return (
            log.Err.msg === "Canister rrkah-fqaaa-aaaaa-aaaaq-cai is stopped"
          );
      })
    ).toBeTruthy();

    // update followees should not be there
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "update_followees";
      })
    ).toBeFalsy();
  });

  it("should update followee successfully ", async () => {
    await manager.startNnsCanister();

    await manager.advanceBlocksAndTimeMinutes(5);

    node = await manager.getNode(node.id);

    for (let followee of node.custom[0].nns.cache.followees) {
      expect(followee[1].followees[0].id).toBe(MOCK_FOLLOWEE_TO_SET_2);
    }
    expect(node.custom[0].nns.cache.followees).toHaveLength(3);

    // update followees should now be there
    expect(
      node.custom[0].nns.internals.activity_log.some((log) => {
        if ("Ok" in log) return log.Ok.operation === "update_followees";
      })
    ).toBeTruthy();
  });

});
