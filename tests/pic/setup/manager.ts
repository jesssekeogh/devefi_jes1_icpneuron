import {
  _SERVICE as NNSVECTOR,
  CreateRequest,
  ModifyNodeRequest,
  ModifyRequest,
  CommonCreateRequest,
  NodeShared,
  LocalNodeId as NodeId,
  GetNodeResponse,
  BatchCommandResponse,
} from "../declarations/nnsvector/nnsvector.did.js";
import {
  _SERVICE as ICRCLEDGER,
  Account,
  TransferResult,
} from "./icrcledger/icrcledger.idl.js";
import {
  _SERVICE as GOVERNANCE,
  idlFactory as governanceIdlFactory,
} from "./nns/governance";
import {
  _SERVICE as LEDGER,
  idlFactory as ledgerIdlFactory,
} from "./nns/ledger";
import {
  Actor,
  PocketIc,
  createIdentity,
  SubnetStateType,
} from "@hadronous/pic";
import { Principal } from "@dfinity/principal";
import {
  GOVERNANCE_CANISTER_ID,
  ICP_LEDGER_CANISTER_ID,
  NNS_ROOT_CANISTER_ID,
} from "./constants.ts";
import { NNSVector, ICRCLedger } from "./index";
import { minterIdentity } from "./nns/identity.ts";
import { NNS_STATE_PATH, NNS_SUBNET_ID } from "./constants.ts";

interface StakeNeuronParams {
  dissolveDelay: bigint;
  followee: bigint;
  dissolving: boolean;
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
  private readonly vectorActor: Actor<NNSVECTOR>;
  private readonly icrcActor: Actor<ICRCLEDGER>;
  private readonly nnsActor: Actor<GOVERNANCE>;
  private readonly ledgerActor: Actor<LEDGER>;

  constructor(
    pic: PocketIc,
    me: ReturnType<typeof createIdentity>,
    vectorActor: Actor<NNSVECTOR>,
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
          subnetId: Principal.fromText(NNS_SUBNET_ID),
        },
      },
    });

    await pic.setTime(new Date().getTime());
    await pic.tick();

    let identity = createIdentity("superSecretAlicePassword");

    // setup ICRC
    let icrcFixture = await ICRCLedger(pic, identity.getPrincipal());

    // setup vector
    let vectorFixture = await NNSVector(pic);

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
  public getVector(): Actor<NNSVECTOR> {
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

  public async advanceTime(mins: number): Promise<void> {
    await this.pic.advanceTime(mins * 60 * 1000);
  }

  public async advanceBlocks(blocks: number): Promise<void> {
    await this.pic.tick(blocks);
  }

  public async advanceBlocksAndTime(rounds: number): Promise<void> {
    for (let i = 0; i < rounds; i++) {
      let mins = 10;
      let blocks = 10;
      await this.pic.advanceTime(mins * 60 * 1000);
      await this.pic.tick(blocks);
    }
  }

  public async createNode(stakeParams: StakeNeuronParams): Promise<NodeShared> {
    let req: CommonCreateRequest = {
      controllers: [{ owner: this.me.getPrincipal(), subaccount: [] }],
      destinations: [
        [{ ic: { owner: this.me.getPrincipal(), subaccount: [] } }],
      ],
      refund: { owner: this.me.getPrincipal(), subaccount: [] },
      ledgers: [{ ic: ICP_LEDGER_CANISTER_ID }],
      sources: [],
      extractors: [],
      affiliate: [],
      temporary: true,
      temp_id: 0,
    };

    let creq: CreateRequest = {
      nns: {
        variables: {
          update_delay_seconds: stakeParams.dissolveDelay,
          update_followee: stakeParams.followee,
          update_dissolving: stakeParams.dissolving,
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
    updateDelaySeconds: [] | [bigint],
    updateFollowee: [] | [bigint],
    updateDissolving: [] | [boolean]
  ): Promise<BatchCommandResponse> {
    let modCustomReq: ModifyRequest = {
      nns: {
        update_delay_seconds: updateDelaySeconds,
        update_dissolving: updateDissolving,
        update_followee: updateFollowee,
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

  public async stakeNeuron(
    stakeAmount: bigint,
    stakeParams: StakeNeuronParams
  ): Promise<NodeShared> {
    let node = await this.createNode(stakeParams);
    await this.advanceBlocksAndTime(1);

    await this.payNodeBill(node);

    await this.advanceBlocksAndTime(2);

    await this.sendIcp(this.getNodeSourceAccount(node), stakeAmount);
    await this.advanceBlocksAndTime(8);

    let refreshedNode = await this.getNode(node.id);
    return refreshedNode;
  }

  public async payNodeBill(node: NodeShared): Promise<void> {
    let billingAccount = node.billing.account;
    await this.sendIcrc(
      billingAccount,
      100_0000_0000n // more than enough
    );
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

  public getNodeSourceAccount(node: NodeShared): Account {
    if (!node || node.sources.length === 0) {
      throw new Error("Invalid node or no sources found");
    }

    let endpoint = node.sources[0].endpoint;

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
