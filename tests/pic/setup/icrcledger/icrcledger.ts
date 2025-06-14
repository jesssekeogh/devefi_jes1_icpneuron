import { resolve } from "node:path";
import { PocketIc } from "@dfinity/pic";
import {
  _SERVICE as ICRCLedgerService,
  idlFactory,
  init,
  LedgerArg,
} from "./declarations/icrcledger.idl";
import { IDL } from "@dfinity/candid";
import { Principal } from "@dfinity/principal";

const WASM_PATH = resolve(__dirname, "../icrcledger/icrcledger.wasm");

export async function ICRCLedger(pic: PocketIc, me: Principal) {
  let ledger_args: LedgerArg = {
    Init: {
      minting_account: {
        owner: me,
        subaccount: [],
      },
      fee_collector_account: [{ owner: me, subaccount: [] }],
      transfer_fee: 10000n,
      decimals: [8],
      token_symbol: "tCOIN",
      token_name: "Test Coin",
      metadata: [],
      initial_balances: [[{ owner: me, subaccount: [] }, 100000000000n]],
      archive_options: {
        num_blocks_to_archive: 10000n,
        trigger_threshold: 9000n,
        controller_id: me,
        max_transactions_per_response: [],
        max_message_size_bytes: [],
        cycles_for_archive_creation: [],
        node_max_memory_size_bytes: [],
      },
      maximum_number_of_accounts: [],
      accounts_overflow_trim_quantity: [],
      max_memo_length: [],
      feature_flags: [{ icrc2: true }],
    },
  };

  const subnets = await pic.getApplicationSubnets();

  const fixture = await pic.setupCanister<ICRCLedgerService>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(init({ IDL }), [ledger_args]),
    targetSubnetId: subnets[0].id,
  });

  return fixture;
}

export default ICRCLedger;
