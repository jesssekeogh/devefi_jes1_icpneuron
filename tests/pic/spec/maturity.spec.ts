import { Setup } from "../setup/setup.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";
import { Maturity } from "../setup/maturity.ts";

describe("Maturity", () => {
  let setup: Setup;
  let maturity: Maturity;
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let isDissolving: boolean = false;
  let followeeNeuronId: bigint;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
    maturity = Maturity.beforeAll(
      setup.getNNS(),
      setup.getIcpLedger(),
      setup.getMe()
    );

    followeeNeuronId = await maturity.createNeuron();

    node = await setup.stakeNeuron(amountToStake, {
      dissolveDelay: dissolveDelayToSet,
      followee: followeeNeuronId,
      dissolving: isDissolving,
    });
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should accrue maturity", async () => {
    await maturity.createMotionProposal(followeeNeuronId);
    await setup.advanceBlocksAndTime(3);

    await setup.advanceTime(20160); // 2 weeks
    await setup.advanceBlocks(10);

    node = await setup.getNode(node.id);

    expect(node.custom.nns_neuron.cache.maturity_e8s_equivalent[0]).toBeGreaterThan(0n);
  });

    it("should spawn maturity", async () => {
      await setup.advanceBlocksAndTime(5)
      node = await setup.getNode(node.id);

      expect(node.custom.nns_neuron.internals.spawning_neurons.length).toBeGreaterThan(0);
      expect(node.custom.nns_neuron.internals.local_idx).toBe(1);
    });

    it("should claim maturity", async () => {
      let oldBalance = await setup.getMyBalances();
      await setup.advanceTime(10160); // 1 week
      await setup.advanceBlocks(10);

      await setup.advanceBlocksAndTime(5)
    
      node = await setup.getNode(node.id);
      expect(node.custom.nns_neuron.internals.spawning_neurons.length).toBe(0);

      let newBalance = await setup.getMyBalances();
      expect(newBalance.icp_tokens).toBeGreaterThan(oldBalance.icp_tokens)
    });
});
