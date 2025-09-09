import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/nns_test_pylon/declarations/nns_test_pylon.did.js";
import { Maturity } from "../setup/maturity.ts";
import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MINIMUM_DISSOLVE_DELAY_DAYS,
  SPLIT_AMOUNT,
  ICP_TRANSACTION_FEE,
  STAKE_MULTIPLIER_FOR_SPLIT,
} from "../setup/constants.ts";
import { createIdentity } from "@dfinity/pic";

describe("Split", () => {
  let manager: Manager;
  let maturity: Maturity;
  let node: NodeShared;
  let proposalNeuronId: bigint;
  let proposalId: bigint;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    maturity = Maturity.beforeAll(manager);
    proposalNeuronId = await maturity.createNeuron();

    // Create and stake a neuron with sufficient stake to split
    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT, // Stake more than usual to have enough to split
      billing_option: 0n,
      neuron_params: {
        dissolve_delay: { DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS },
        followee: { None: null },
        dissolve_status: { Locked: null },
        hotkey: { None: null },
        visibility: { Private: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should have initial neuron with correct setup", async () => {
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(
      AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT - EXPECTED_TRANSACTION_FEES
    );

    // Verify neuron_cache contains the main neuron
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(1);

    // Verify main neuron in cache matches the cache
    const mainNeuronInCache =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache[0];
    expect(mainNeuronInCache.neuron_id[0]).toBe(
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    );
    expect(mainNeuronInCache.cached_neuron_stake_e8s[0]).toBe(
      AMOUNT_TO_STAKE * STAKE_MULTIPLIER_FOR_SPLIT - EXPECTED_TRANSACTION_FEES
    );

    // Verify initial variables
    expect(
      node.custom[0].devefi_jes1_icpneuron.variables.dissolve_delay
    ).toEqual({ DelayDays: MINIMUM_DISSOLVE_DELAY_DAYS });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.followee).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.hotkey).toEqual({
      None: null,
    });
    expect(node.custom[0].devefi_jes1_icpneuron.variables.visibility).toEqual({
      Private: null,
    });
  });

  it("should split multiple neurons for voting", async () => {
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];
    const initialStake =
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0];

    const numberOfSplits = 4; // Create 4 additional neurons for total of 5 (1 main + 4 new splits)

    // Perform multiple splits in a loop
    for (let i = 0; i < numberOfSplits; i++) {
      const splitResult = await manager.getVector().icpneuron_split({
        vid: node.id,
        caller_subaccount: [],
        amount_e8s: SPLIT_AMOUNT,
        neuronId: mainNeuronId,
      });

      expect("ok" in splitResult).toBe(true);
    }

    // Advance time after each split to allow processing
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    // Verify we now have 5 neurons total (main + 4 splits)
    expect(node.custom[0].devefi_jes1_icpneuron.neuron_cache).toHaveLength(5);

    // Verify main neuron stake is reduced by all splits
    const expectedMainStake =
      initialStake - BigInt(numberOfSplits) * SPLIT_AMOUNT;
    expect(
      node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    ).toBe(expectedMainStake);

    // Verify main neuron in cache
    const mainNeuronInCache =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.find(
        (neuron) => neuron.neuron_id[0] === mainNeuronId
      );
    expect(mainNeuronInCache.cached_neuron_stake_e8s[0]).toBe(
      expectedMainStake
    );

    // Verify all split neurons have correct stakes
    const splitNeurons =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.filter(
        (neuron) => neuron.neuron_id[0] !== mainNeuronId
      );
    expect(splitNeurons).toHaveLength(numberOfSplits); // +1 for previous split
    splitNeurons.forEach((splitNeuron) => {
      expect(splitNeuron.followees).toHaveLength(0);
      expect(splitNeuron.cached_neuron_stake_e8s[0]).toBe(
        SPLIT_AMOUNT - ICP_TRANSACTION_FEE
      );
    });
  });

  it("should create a proposal for voting", async () => {
    proposalId = await maturity.createMotionProposal(proposalNeuronId);
    await manager.advanceBlocksAndTimeDays(1);

    expect(proposalId).toBeDefined();
  });

  it("should not votes if caller is not a controller", async () => {
    const pylon = manager.getVector();

    pylon.setIdentity(createIdentity("superSecretBobPassword"));

    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    const voteResult = await pylon.icpneuron_vote({
      vid: node.id,
      caller_subaccount: [], // null
      neuronId: mainNeuronId,
      proposal: proposalId,
      vote: 1, // yes vote
    });

    expect("err" in voteResult).toBe(true);
    expect(voteResult).toEqual({ err: "Not a controller" });

    // set it back
    pylon.setIdentity(createIdentity("superSecretAlicePassword"));
  });

  it("should not vote with invalid neuron ID", async () => {
    // Use a fake neuron ID that doesn't exist
    const fakeNeuronId = 999999999999999999n;

    // Perform the split with invalid neuron ID
    const splitResult = await manager.getVector().icpneuron_vote({
      vid: node.id,
      caller_subaccount: [], // null
      neuronId: fakeNeuronId,
      proposal: proposalId,
      vote: 1, // yes vote
    });

    expect("err" in splitResult).toBe(true);
    expect(splitResult).toEqual({
      err: `Neuron ID 999_999_999_999_999_999 not found in node's neuron cache`,
    });
  });

  it("should vote yes with main neuron", async () => {
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    const voteResult = await manager.getVector().icpneuron_vote({
      vid: node.id,
      caller_subaccount: [], // null
      neuronId: mainNeuronId,
      proposal: proposalId,
      vote: 1, // yes vote
    });

    expect("ok" in voteResult).toBe(true);
    expect(voteResult).toEqual({ ok: null });

    // Advance time to allow the vote to be processed
    await manager.advanceBlocksAndTimeMinutes(1);
    node = await manager.getNode(node.id);

    // Verify the vote was logged in activity
    const voteActivity = node.custom[0].devefi_jes1_icpneuron.log.find(
      (activity) => "Ok" in activity && activity.Ok.operation === "vote"
    );
    expect(voteActivity).toBeDefined();
    expect("Ok" in voteActivity).toBe(true);
  });

  it("should vote no with 2 split neurons on the same proposal", async () => {
    // Get all split neurons (excluding the main neuron)
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    const splitNeurons =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.filter(
        (neuron) => neuron.neuron_id[0] !== mainNeuronId
      );

    expect(splitNeurons.length).toBeGreaterThanOrEqual(4); // Need at least 4 split neurons

    // Vote no (vote: 2) with first 2 split neurons
    const noVoteNeurons = splitNeurons.slice(0, 2);

    for (const splitNeuron of noVoteNeurons) {
      const voteResult = await manager.getVector().icpneuron_vote({
        vid: node.id,
        caller_subaccount: [], // null
        neuronId: splitNeuron.neuron_id[0],
        proposal: proposalId,
        vote: 2, // no vote
      });

      expect("ok" in voteResult).toBe(true);
      expect(voteResult).toEqual({ ok: null });
    }

    // Advance time to allow the votes to be processed
    await manager.advanceBlocksAndTimeMinutes(1);
    node = await manager.getNode(node.id);

    // Verify the no votes were logged in activity
    const voteActivities = node.custom[0].devefi_jes1_icpneuron.log.filter(
      (activity) => "Ok" in activity && activity.Ok.operation === "vote"
    );
    expect(voteActivities.length).toBeGreaterThanOrEqual(3); // main neuron + 2 no votes
  });

  it("should vote yes with 2 other split neurons on the same proposal", async () => {
    // Get all split neurons (excluding the main neuron)
    const mainNeuronId =
      node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0];

    const splitNeurons =
      node.custom[0].devefi_jes1_icpneuron.neuron_cache.filter(
        (neuron) => neuron.neuron_id[0] !== mainNeuronId
      );

    expect(splitNeurons.length).toBeGreaterThanOrEqual(4); // Need at least 4 split neurons

    // Vote yes (vote: 1) with next 2 split neurons (neurons 3 and 4)
    const yesVoteNeurons = splitNeurons.slice(2, 4);

    for (const splitNeuron of yesVoteNeurons) {
      const voteResult = await manager.getVector().icpneuron_vote({
        vid: node.id,
        caller_subaccount: [], // null
        neuronId: splitNeuron.neuron_id[0],
        proposal: proposalId,
        vote: 1, // yes vote
      });

      expect("ok" in voteResult).toBe(true);
      expect(voteResult).toEqual({ ok: null });
    }

    // Advance time to allow the votes to be processed
    await manager.advanceBlocksAndTimeMinutes(1);
    node = await manager.getNode(node.id);

    // Verify all votes were logged in activity
    const voteActivities = node.custom[0].devefi_jes1_icpneuron.log.filter(
      (activity) => "Ok" in activity && activity.Ok.operation === "vote"
    );
    // Should have votes from: main neuron (1) + 2 no votes + 2 yes votes = 5 total
    expect(voteActivities.length).toBe(5);

    // All vote activities should be successful
    voteActivities.forEach((activity) => {
      expect("Ok" in activity).toBe(true);
    });
  });
});
