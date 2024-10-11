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

    let source = await setup.getNodeSourceAccount(node);
    let destination = await setup.getNodeDestinationAccount(node);

  });
});
