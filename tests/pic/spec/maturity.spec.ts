import { Setup } from "../setup/setup.ts";
import { NodeShared } from "../declarations/nnsvector/nnsvector.did.js";

describe("Stake", () => {
  let setup: Setup;
  let node: NodeShared;
  let amountToStake: bigint = 10_0000_0000n;
  let expectedTransactionFees: bigint = 20_000n;
  let dissolveDelayToSet: bigint = 15897600n; // 184 days
  let followeeToSet: bigint = 6914974521667616512n;
  let isDissolving: boolean = false;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
    node = await setup.stakeNeuron(amountToStake, {
      dissolveDelay: dissolveDelayToSet,
      followee: followeeToSet,
      dissolving: isDissolving,
    });
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should accrue maturity", async () => {
    // TODO create proposals and vote on them and pass time to gain maturity
    // TODO expect maturity
  });

//   it("should spawn maturity", async () => {
//     // TODO expect maturity spawned and in spawning neuron cache
//     // TODO expect local_idx to increase by one
//   });

//   it("should claim maturity", async () => {
//     // TODO expect maturity to be claimed and set to destination address
//     // TODO expect neuron to be removed from spawning neuron cache
//   });

});
