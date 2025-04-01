import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nnsvector/declarations/nnsvector.did.js";
import {
  AMOUNT_TO_STAKE,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";

describe("Empty", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    node = await manager.createNode({
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

  it("should create an empty node", async () => {
    await manager.advanceBlocksAndTimeDays(3);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeUndefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBeUndefined();
  });

  it("should not refresh empty node every 3 minutes", async () => {
    // Get current updating timestamp
    const initialTimestamp = 
      node.custom[0].devefi_jes1_icpneuron.internals.updating;
    
    // Advance time by 3 minutes and a bit to allow for processing
    await manager.advanceBlocksAndTimeMinutes(5);
    
    // Get the node again
    node = await manager.getNode(node.id);
    
    // Check that the timestamp has not changed
    const newTimestamp = 
      node.custom[0].devefi_jes1_icpneuron.internals.updating;
    
    // Use deep equality to compare objects
    expect(newTimestamp).toEqual(initialTimestamp);
    
    // Let's verify again with another time advancement to be sure
    await manager.advanceBlocksAndTimeMinutes(5);
    
    node = await manager.getNode(node.id);
    const finalTimestamp = 
      node.custom[0].devefi_jes1_icpneuron.internals.updating;
    
    // Should still match the initial timestamp
    expect(finalTimestamp).toEqual(initialTimestamp);
  });
});
