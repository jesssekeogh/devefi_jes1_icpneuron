import { _SERVICE as GOVERNANCE } from "./nns/governance";
import { _SERVICE as LEDGER, SubAccount, Account } from "./nns/ledger";
import { Actor } from "@hadronous/pic";
import { createHash, randomBytes } from "node:crypto";
import { Principal } from "@dfinity/principal";
import { GOVERNANCE_CANISTER_ID } from "./constants";
import { Manager } from "./manager";

// helper class to create maturity in neurons
export class Maturity {
  private readonly owner: Principal;
  private readonly nnsActor: Actor<GOVERNANCE>;
  private readonly ledgerActor: Actor<LEDGER>;

  constructor(manager: Manager) {
    this.nnsActor = manager.getNNS();
    this.ledgerActor = manager.getIcpLedger();
    this.owner = manager.getMe();
  }

  // pass in nns and icp ledger from node class
  public static beforeAll(manager: Manager): Maturity {
    return new Maturity(manager);
  }

  private generateNonce(): bigint {
    return randomBytes(8).readBigUint64BE();
  }

  private getNeuronSubaccount(
    controller: Principal,
    nonce: bigint
  ): SubAccount {
    const hasher = createHash("sha256");
    hasher.update(new Uint8Array([0x0c]));
    hasher.update(Buffer.from("neuron-stake"));
    hasher.update(controller.toUint8Array());
    hasher.update(this.bigEndianU64(nonce));

    return hasher.digest();
  }

  private bigEndianU64(value: bigint): Uint8Array {
    const buffer = Buffer.alloc(8);
    buffer.writeBigUInt64BE(value);
    return buffer;
  }

  public async createNeuron(): Promise<bigint> {
    let nonce = this.generateNonce();

    let neuronSubaccount = this.getNeuronSubaccount(this.owner, nonce);

    let to: Account = {
      owner: GOVERNANCE_CANISTER_ID,
      subaccount: [neuronSubaccount],
    };

    await this.ledgerActor.icrc1_transfer({
      from_subaccount: [],
      to: to,
      amount: 10_0000_0000n,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    const claimResponse =
      await this.nnsActor.claim_or_refresh_neuron_from_account({
        controller: [this.owner],
        memo: nonce,
      });

    const claimResult = claimResponse.result[0];

    if (!claimResult) {
      throw new Error("Failed to create neuron");
    }

    if ("Error" in claimResult) {
      const error = claimResult.Error;
      throw new Error(`${error.error_type}: ${error.error_message}`);
    }

    const neuronId = claimResult.NeuronId;

    const dissolveDelayResponse = await this.nnsActor.manage_neuron({
      id: [neuronId],
      command: [
        {
          Configure: {
            operation: [
              {
                IncreaseDissolveDelay: {
                  additional_dissolve_delay_seconds: 60 * 60 * 24 * 7 * 52 * 1, // 1 year
                },
              },
            ],
          },
        },
      ],
      neuron_id_or_subaccount: [],
    });

    const dissolveDelayResult = dissolveDelayResponse.command[0];
    if (!dissolveDelayResult) {
      throw new Error("Failed to set dissolve delay");
    }
    if ("Error" in dissolveDelayResult) {
      throw new Error(
        `${dissolveDelayResult.Error.error_type}: ${dissolveDelayResult.Error.error_message}`
      );
    }

    return neuronId.id;
  }

  public async createMotionProposal(neuronId: bigint): Promise<bigint> {
    const response = await this.nnsActor.manage_neuron({
      id: [{ id: neuronId }],
      command: [
        {
          MakeProposal: {
            // TODO test different types of proposals
            url: "",
            title: ["Oscar"],
            summary: "Golden Labrador Retriever",
            action: [
              {
                Motion: { motion_text: "Good Boy?" },
              },
            ],
          },
        },
      ],
      neuron_id_or_subaccount: [],
    });
    const result = response.command[0];

    if (!result) {
      throw new Error("Failed to create proposal");
    }

    if ("Error" in result) {
      throw new Error(
        `${result.Error.error_type}: ${result.Error.error_message}`
      );
    }
    //@ts-ignore
    return result.MakeProposal.proposal_id[0].id;
  }
}
