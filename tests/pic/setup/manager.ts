import {
  _SERVICE as NNSTESTPYLON,
  CreateRequest,
  ModifyNodeRequest,
  ModifyRequest,
  CommonCreateRequest,
  NodeShared,
  LocalNodeId as NodeId,
  GetNodeResponse,
  BatchCommandResponse,
} from "./nns_test_pylon/declarations/nns_test_pylon.did.js";
import {
  _SERVICE as ICRCLEDGER,
  Account,
  TransferResult,
} from "./icrcledger/declarations/icrcledger.idl.js";
import {
  _SERVICE as GOVERNANCE,
  idlFactory as governanceIdlFactory,
} from "./nns/governance";
import {
  _SERVICE as LEDGER,
  idlFactory as ledgerIdlFactory,
} from "./nns/ledger";
import { Actor, PocketIc, createIdentity, SubnetStateType } from "@dfinity/pic";
import { Principal } from "@dfinity/principal";
import {
  GOVERNANCE_CANISTER_ID,
  ICP_LEDGER_CANISTER_ID,
  NNS_ROOT_CANISTER_ID,
} from "./constants.ts";
import { NnsTestPylon, ICRCLedger } from "./index";
import { minterIdentity } from "./nns/identity.ts";
import { NNS_STATE_PATH, NNS_SUBNET_ID } from "./constants.ts";
import Router from "./router/router.ts";

interface NeuronParams {
  dissolve_delay: { Default: null } | { DelayDays: bigint };
  followee: { Default: null } | { FolloweeId: bigint };
  dissolve_status: { Dissolving: null } | { Locked: null };
}

interface StakeNodeParams {
  stake_amount: bigint;
  billing_option: bigint;
  neuron_params: NeuronParams;
}

interface NeuronStates {
  locked: number;
  dissolving: number;
  unlocked: number;
  spawning: number;
}

export class Manager {
  private readonly me: ReturnType<typeof createIdentity>;
  private readonly pic: PocketIc;
  private readonly vectorActor: Actor<NNSTESTPYLON>;
  private readonly icrcActor: Actor<ICRCLEDGER>;
  private readonly nnsActor: Actor<GOVERNANCE>;
  private readonly ledgerActor: Actor<LEDGER>;

  constructor(
    pic: PocketIc,
    me: ReturnType<typeof createIdentity>,
    vectorActor: Actor<NNSTESTPYLON>,
    icrcActor: Actor<ICRCLEDGER>,
    nnsActor: Actor<GOVERNANCE>,
    ledgerActor: Actor<LEDGER>
  ) {
    this.pic = pic;
    this.me = me;
    this.vectorActor = vectorActor;
    this.icrcActor = icrcActor;
    this.nnsActor = nnsActor;
    this.ledgerActor = ledgerActor;

    // set identitys as me
    this.nnsActor.setIdentity(this.me);
    this.ledgerActor.setIdentity(this.me);
    this.vectorActor.setIdentity(this.me);
    this.icrcActor.setIdentity(this.me);
  }

  public static async beforeAll(): Promise<Manager> {
    let pic = await PocketIc.create(process.env.PIC_URL, {
      nns: {
        state: {
          type: SubnetStateType.FromPath,
          path: NNS_STATE_PATH,
        },
      },
      application: [{ state: { type: SubnetStateType.New } }],
    });

    await pic.setTime(new Date().getTime());
    await pic.tick();

    let identity = createIdentity("superSecretAlicePassword");

    // setup ICRC
    let icrcFixture = await ICRCLedger(pic, identity.getPrincipal());

    // setup chrono router
    // we are not testing the router here, but we need it to spin up a pylon
    // pass time to allow router to setup slices
    await Router(pic);
    await pic.advanceTime(240 * 60 * 1000);
    await pic.tick(240);

    // setup vector
    let vectorFixture = await NnsTestPylon(pic);

    // setup nns
    let govActor = pic.createActor<GOVERNANCE>(
      governanceIdlFactory,
      GOVERNANCE_CANISTER_ID
    );

    // setup icp ledger
    let ledgerActor = pic.createActor<LEDGER>(
      ledgerIdlFactory,
      ICP_LEDGER_CANISTER_ID
    );

    // set identity as minter
    ledgerActor.setIdentity(minterIdentity);
    // mint ICP tokens
    await ledgerActor.icrc1_transfer({
      from_subaccount: [],
      to: { owner: identity.getPrincipal(), subaccount: [] },
      amount: 100000000000n,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    return new Manager(
      pic,
      identity,
      vectorFixture.actor,
      icrcFixture.actor,
      govActor,
      ledgerActor
    );
  }

  public async afterAll(): Promise<void> {
    await this.pic.tearDown();
  }

  public async stopNnsCanister(): Promise<void> {
    this.pic.stopCanister({
      canisterId: GOVERNANCE_CANISTER_ID,
      sender: NNS_ROOT_CANISTER_ID,
    });
  }

  public async stopIcpLedgerCanister(): Promise<void> {
    this.pic.stopCanister({
      canisterId: ICP_LEDGER_CANISTER_ID,
      sender: NNS_ROOT_CANISTER_ID,
    });
  }

  public async startNnsCanister(): Promise<void> {
    this.pic.startCanister({
      canisterId: GOVERNANCE_CANISTER_ID,
      sender: NNS_ROOT_CANISTER_ID,
    });
  }

  public async startIcpLedgerCanister(): Promise<void> {
    this.pic.startCanister({
      canisterId: ICP_LEDGER_CANISTER_ID,
      sender: NNS_ROOT_CANISTER_ID,
    });
  }

  public getMe(): Principal {
    return this.me.getPrincipal();
  }
  public getVector(): Actor<NNSTESTPYLON> {
    return this.vectorActor;
  }

  public getNNS(): Actor<GOVERNANCE> {
    return this.nnsActor;
  }

  public getIcrcLedger(): Actor<ICRCLEDGER> {
    return this.icrcActor;
  }

  public getIcpLedger(): Actor<LEDGER> {
    return this.ledgerActor;
  }

  public async getNow(): Promise<bigint> {
    let time = await this.pic.getTime();
    return BigInt(Math.trunc(time));
  }

  public async advanceTime(mins: number): Promise<void> {
    await this.pic.advanceTime(mins * 60 * 1000);
  }

  public async advanceBlocks(blocks: number): Promise<void> {
    await this.pic.tick(blocks);
  }

  // used for when a refresh is pending on a node
  public async advanceBlocksAndTimeMinutes(rounds: number): Promise<void> {
    let mins = 10; // 10 mins
    let blocks = 10;
    for (let i = 0; i < rounds; i++) {
      await this.pic.advanceTime(mins * 60 * 1000);
      await this.pic.tick(blocks);
    }
  }

  public async advanceBlocksAndTimeHours(rounds: number): Promise<void> {
    const sixHoursMins = 6 * 60; // 6 hours
    const shortIntervalMins = 10; // 10 minutes
    const blocksForSixHours = 10; // Blocks for 6 hours
    const blocksForShortInterval = 5; // Blocks for 10 minutes

    for (let i = 0; i < rounds; i++) {
      await this.pic.advanceTime(sixHoursMins * 60 * 1000); // Convert minutes to milliseconds
      await this.pic.tick(blocksForSixHours);

      // Advance 10 minutes (to process things)
      await this.pic.advanceTime(shortIntervalMins * 60 * 1000); // Convert minutes to milliseconds
      await this.pic.tick(blocksForShortInterval);
    }
  }

  // Used for when no refresh is pending, a node is updated once every 12 hours (with 10 minutes to process)
  public async advanceBlocksAndTimeDays(rounds: number): Promise<void> {
    const halfDayMins = 12 * 60; // 12 hours
    const shortIntervalMins = 10; // 10 minutes
    const blocksForHalfDay = 10; // Blocks for 12 hours
    const blocksForShortInterval = 5; // Blocks for 10 minutes

    for (let i = 0; i < rounds; i++) {
      // run this twice (24 hours)
      for (let x = 0; x < 2; x++) {
        // Advance 12 hours
        await this.pic.advanceTime(halfDayMins * 60 * 1000); // Convert minutes to milliseconds
        await this.pic.tick(blocksForHalfDay);

        // Advance 10 minutes
        await this.pic.advanceTime(shortIntervalMins * 60 * 1000); // Convert minutes to milliseconds
        await this.pic.tick(blocksForShortInterval);
      }
    }
  }

  public convertDaysToSeconds(days: bigint): bigint {
    const secondsInADay = 24n * 60n * 60n; // Calculate seconds in a day using bigints
    return days * secondsInADay; // Multiply days by seconds in a day
  }

  public convertNanosToMillis(nanoTimestamp: bigint): bigint {
    return nanoTimestamp / 1_000_000n;
  }

  public async createNode(stakeParams: StakeNodeParams): Promise<NodeShared> {
    let [
      {
        endpoint: {
          // @ts-ignore
          ic: { account },
        },
      },
    ] = await this.vectorActor.icrc55_accounts({
      owner: this.me.getPrincipal(),
      subaccount: [],
    });

    await this.sendIcrc(
      account,
      100_0001_0000n // more than enough (10_000 for fees)
    );

    await this.advanceBlocksAndTimeMinutes(3);

    let req: CommonCreateRequest = {
      controllers: [{ owner: this.me.getPrincipal(), subaccount: [] }],
      destinations: [
        [{ ic: { owner: this.me.getPrincipal(), subaccount: [] } }],
        [{ ic: { owner: this.me.getPrincipal(), subaccount: [] } }],
      ],
      refund: { owner: this.me.getPrincipal(), subaccount: [] },
      ledgers: [{ ic: ICP_LEDGER_CANISTER_ID }],
      sources: [],
      extractors: [],
      affiliate: [],
      temporary: false,
      billing_option: stakeParams.billing_option,
      initial_billing_amount: [100_0000_0000n],
      temp_id: 0,
    };

    let creq: CreateRequest = {
      devefi_jes1_icpneuron: {
        variables: {
          dissolve_delay: stakeParams.neuron_params.dissolve_delay,
          dissolve_status: stakeParams.neuron_params.dissolve_status,
          followee: stakeParams.neuron_params.followee,
        },
      },
    };

    let resp = await this.vectorActor.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ create_node: [req, creq] }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].create_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].create_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].create_node.ok;
  }

  public async modifyNode(
    nodeId: number,
    updateDelaySeconds: [] | [{ Default: null } | { DelayDays: bigint }],
    updateFollowee: [] | [{ Default: null } | { FolloweeId: bigint }],
    updateDissolving: [] | [{ Dissolving: null } | { Locked: null }]
  ): Promise<BatchCommandResponse> {
    let modCustomReq: ModifyRequest = {
      devefi_jes1_icpneuron: {
        dissolve_delay: updateDelaySeconds,
        dissolve_status: updateDissolving,
        followee: updateFollowee,
      },
    };

    let modReq: ModifyNodeRequest = [
      nodeId,
      [
        {
          destinations: [],
          refund: [],
          sources: [],
          extractors: [],
          controllers: [[{ owner: this.me.getPrincipal(), subaccount: [] }]],
          active: [],
        },
      ],
      [modCustomReq],
    ];

    let resp = await this.vectorActor.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ modify_node: modReq }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].modify_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].modify_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].modify_node.ok;
  }

  public async deleteNode(nodeId: number) {
    let resp = await this.vectorActor.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ delete_node: nodeId }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].delete_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].delete_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].delete_node.ok;
  }

  public async stakeNeuron(stakeParams: StakeNodeParams): Promise<NodeShared> {
    let node = await this.createNode(stakeParams);
    await this.advanceBlocksAndTimeMinutes(3);

    await this.sendIcp(
      this.getNodeSourceAccount(node, 0),
      stakeParams.stake_amount
    );
    await this.advanceBlocksAndTimeMinutes(8);

    let refreshedNode = await this.getNode(node.id);
    return refreshedNode;
  }

  public async getNode(nodeId: NodeId): Promise<GetNodeResponse> {
    let resp = await this.vectorActor.icrc55_get_nodes([{ id: nodeId }]);
    if (resp[0][0] === undefined) throw new Error("Node not found");
    return resp[0][0];
  }

  public async sendIcrc(to: Account, amount: bigint): Promise<TransferResult> {
    let txresp = await this.icrcActor.icrc1_transfer({
      from_subaccount: [],
      to: to,
      amount: amount,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    if (!("Ok" in txresp)) {
      throw new Error("Transaction failed");
    }

    return txresp;
  }

  public async sendIcp(to: Account, amount: bigint): Promise<TransferResult> {
    let txresp = await this.ledgerActor.icrc1_transfer({
      from_subaccount: [],
      to: to,
      amount: amount,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    if (!("Ok" in txresp)) {
      throw new Error("Transaction failed");
    }

    return txresp;
  }

  public async getMyBalances() {
    let icrc = await this.icrcActor.icrc1_balance_of({
      owner: this.me.getPrincipal(),
      subaccount: [],
    });

    let icp = await this.ledgerActor.icrc1_balance_of({
      owner: this.me.getPrincipal(),
      subaccount: [],
    });

    return { icrc_tokens: icrc, icp_tokens: icp };
  }

  public async getBillingBalances() {
    let author = Principal.fromText(
      "jv4ws-fbili-a35rv-xd7a5-xwvxw-trink-oluun-g7bcp-oq5f6-35cba-vqe"
    );
    // return other balances to check things out
    let icrc = await this.icrcActor.icrc1_balance_of({
      owner: author,
      subaccount: [],
    });

    let icp = await this.ledgerActor.icrc1_balance_of({
      owner: author,
      subaccount: [],
    });

    return { icrc_tokens: icrc, icp_tokens: icp };
  }

  public getNodeSourceAccount(node: NodeShared, port: number): Account {
    if (!node || node.sources.length === 0) {
      throw new Error("Invalid node or no sources found");
    }

    let endpoint = node.sources[port].endpoint;

    if ("ic" in endpoint) {
      return endpoint.ic.account;
    }

    throw new Error("Invalid endpoint type: 'ic' endpoint expected");
  }

  public async getSourceBalance(nodeId: NodeId): Promise<bigint> {
    let node = await this.getNode(nodeId);
    if (node === undefined) return 0n;

    return node.sources[0].balance;
  }

  public getNodeDestinationAccount(node: NodeShared): Account {
    if (!node || node.destinations.length === 0) {
      throw new Error("Invalid node or no sources found");
    }

    let endpoint = node.destinations[0].endpoint;

    if ("ic" in endpoint && endpoint.ic.account.length > 0) {
      return endpoint.ic.account[0];
    }

    throw new Error("Invalid endpoint type: 'ic' endpoint expected");
  }

  public getNeuronStates(): NeuronStates {
    return {
      locked: 1,
      dissolving: 2,
      unlocked: 3,
      spawning: 4,
    };
  }
}
