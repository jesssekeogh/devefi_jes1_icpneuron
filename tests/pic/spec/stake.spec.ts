import { Setup } from "../setup/setup.ts";

describe("Stake", () => {
  let setup: Setup;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should stake neuron", async () => {
    let node = await setup.createNode();
    await setup.advanceBlocksAndTime(2, 3);

    await setup.sendIcp(setup.getNodeSourceAccount(node), 10_0000_0000n);
    await setup.advanceBlocksAndTime(2, 3);
    await setup.advanceBlocksAndTime(6, 6);
    await setup.advanceBlocksAndTime(6, 6);

    let refNode = await setup.getNode(node.id);
    expect(refNode.custom.nns_neuron.cache.neuron_id).toHaveLength(1);
    // TODO check amount
    // TODO Set dissolve delay and check dissolve delay (check if can increase?)
  });

  // TODO set followee and check followees and reset again and check again
  // TODO Increase Stake and check refresh
  // TODO set dissolving and check dissolving and unset etc
  // TODO Disburse a dissolved neurons
  // TODO multiple neurons
});
