import { _SERVICE as NNSVECTOR } from "../declarations/nnsvector/nnsvector.did.js";
import { _SERVICE as ICRCLEDGER } from "../setup/icrcledger/icrcledger.idl.js";
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
  NNS_STATE_PATH,
  NNS_SUBNET_ID,
} from "./constants";
import { NNSVector, ICRCLedger } from "./index";

export class Setup {
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
  }

  public static async beforeAll(): Promise<Setup> {
    // setup pocket IC
    let pic = await PocketIc.create(process.env.PIC_URL, {
      nns: {
        state: {
          type: SubnetStateType.FromPath,
          path: NNS_STATE_PATH,
          subnetId: Principal.fromText(NNS_SUBNET_ID),
        },
      },
    });

    let me = createIdentity("superSecretAlicePassword");

    // setup ICRC
    let icrcFixture = await ICRCLedger(pic, me.getPrincipal());

    // setup vector
    let vectorFixture = await NNSVector(
      pic,
      GOVERNANCE_CANISTER_ID,
      ICP_LEDGER_CANISTER_ID,
      icrcFixture.canisterId
    );

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

    return new Setup(
      pic,
      me,
      vectorFixture.actor,
      icrcFixture.actor,
      govActor,
      ledgerActor
    );
  }

  public async afterAll(): Promise<void> {
    await this.pic.tearDown();
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
  
}
