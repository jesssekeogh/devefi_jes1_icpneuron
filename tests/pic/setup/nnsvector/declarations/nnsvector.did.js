export const idlFactory = ({ IDL }) => {
  const ArchivedTransactionResponse = IDL.Rec();
  const Value = IDL.Rec();
  const Info = IDL.Record({
    'pending' : IDL.Nat,
    'last_indexed_tx' : IDL.Nat,
    'errors' : IDL.Nat,
    'lastTxTime' : IDL.Nat64,
    'accounts' : IDL.Nat,
    'actor_principal' : IDL.Opt(IDL.Principal),
    'reader_instructions_cost' : IDL.Nat64,
    'sender_instructions_cost' : IDL.Nat64,
  });
  const Info__1 = IDL.Record({
    'pending' : IDL.Nat,
    'last_indexed_tx' : IDL.Nat,
    'errors' : IDL.Nat,
    'lastTxTime' : IDL.Nat64,
    'accounts' : IDL.Nat,
    'actor_principal' : IDL.Principal,
    'reader_instructions_cost' : IDL.Nat64,
    'sender_instructions_cost' : IDL.Nat64,
  });
  const LedgerInfo__1 = IDL.Record({
    'id' : IDL.Principal,
    'info' : IDL.Variant({ 'icp' : Info, 'icrc' : Info__1 }),
  });
  const GetArchivesArgs = IDL.Record({ 'from' : IDL.Opt(IDL.Principal) });
  const GetArchivesResultItem = IDL.Record({
    'end' : IDL.Nat,
    'canister_id' : IDL.Principal,
    'start' : IDL.Nat,
  });
  const GetArchivesResult = IDL.Vec(GetArchivesResultItem);
  const TransactionRange = IDL.Record({
    'start' : IDL.Nat,
    'length' : IDL.Nat,
  });
  const GetBlocksArgs = IDL.Vec(TransactionRange);
  const ValueMap = IDL.Tuple(IDL.Text, Value);
  Value.fill(
    IDL.Variant({
      'Int' : IDL.Int,
      'Map' : IDL.Vec(ValueMap),
      'Nat' : IDL.Nat,
      'Blob' : IDL.Vec(IDL.Nat8),
      'Text' : IDL.Text,
      'Array' : IDL.Vec(Value),
    })
  );
  const GetTransactionsResult = IDL.Record({
    'log_length' : IDL.Nat,
    'blocks' : IDL.Vec(
      IDL.Record({ 'id' : IDL.Nat, 'block' : IDL.Opt(Value) })
    ),
    'archived_blocks' : IDL.Vec(ArchivedTransactionResponse),
  });
  const GetTransactionsFn = IDL.Func(
      [IDL.Vec(TransactionRange)],
      [GetTransactionsResult],
      ['query'],
    );
  ArchivedTransactionResponse.fill(
    IDL.Record({
      'args' : IDL.Vec(TransactionRange),
      'callback' : GetTransactionsFn,
    })
  );
  const GetBlocksResult = IDL.Record({
    'log_length' : IDL.Nat,
    'blocks' : IDL.Vec(
      IDL.Record({ 'id' : IDL.Nat, 'block' : IDL.Opt(Value) })
    ),
    'archived_blocks' : IDL.Vec(ArchivedTransactionResponse),
  });
  const DataCertificate = IDL.Record({
    'certificate' : IDL.Vec(IDL.Nat8),
    'hash_tree' : IDL.Vec(IDL.Nat8),
  });
  const BlockType = IDL.Record({ 'url' : IDL.Text, 'block_type' : IDL.Text });
  const Account = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const AccountsRequest = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const EndpointIC = IDL.Record({
    'ledger' : IDL.Principal,
    'account' : Account,
  });
  const EndpointOther = IDL.Record({
    'platform' : IDL.Nat64,
    'ledger' : IDL.Vec(IDL.Nat8),
    'account' : IDL.Vec(IDL.Nat8),
  });
  const Endpoint = IDL.Variant({ 'ic' : EndpointIC, 'other' : EndpointOther });
  const AccountEndpoint = IDL.Record({
    'balance' : IDL.Nat,
    'endpoint' : Endpoint,
  });
  const AccountsResponse = IDL.Vec(AccountEndpoint);
  const Controller = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const LocalNodeId = IDL.Nat32;
  const EndpointIdx = IDL.Nat8;
  const InputAddress = IDL.Variant({
    'ic' : Account,
    'other' : IDL.Vec(IDL.Nat8),
    'temp' : IDL.Record({ 'id' : IDL.Nat32, 'source_idx' : EndpointIdx }),
  });
  const CommonModifyRequest = IDL.Record({
    'active' : IDL.Opt(IDL.Bool),
    'controllers' : IDL.Opt(IDL.Vec(Controller)),
    'extractors' : IDL.Opt(IDL.Vec(LocalNodeId)),
    'destinations' : IDL.Opt(IDL.Vec(IDL.Opt(InputAddress))),
    'sources' : IDL.Opt(IDL.Vec(IDL.Opt(InputAddress))),
    'refund' : IDL.Opt(Account),
  });
  const DissolveDelay = IDL.Variant({
    'Default' : IDL.Null,
    'DelayDays' : IDL.Nat64,
  });
  const DissolveStatus = IDL.Variant({
    'Locked' : IDL.Null,
    'Dissolving' : IDL.Null,
  });
  const Followee = IDL.Variant({
    'Default' : IDL.Null,
    'FolloweeId' : IDL.Nat64,
  });
  const ModifyRequest__1 = IDL.Record({
    'dissolve_delay' : IDL.Opt(DissolveDelay),
    'dissolve_status' : IDL.Opt(DissolveStatus),
    'followee' : IDL.Opt(Followee),
  });
  const ModifyRequest = IDL.Variant({
    'devefi_jes1_icpneuron' : ModifyRequest__1,
  });
  const ModifyNodeRequest = IDL.Tuple(
    LocalNodeId,
    IDL.Opt(CommonModifyRequest),
    IDL.Opt(ModifyRequest),
  );
  const SupportedLedger = IDL.Variant({
    'ic' : IDL.Principal,
    'other' : IDL.Record({
      'platform' : IDL.Nat64,
      'ledger' : IDL.Vec(IDL.Nat8),
    }),
  });
  const CommonCreateRequest = IDL.Record({
    'controllers' : IDL.Vec(Controller),
    'extractors' : IDL.Vec(LocalNodeId),
    'temp_id' : IDL.Nat32,
    'billing_option' : IDL.Nat,
    'destinations' : IDL.Vec(IDL.Opt(InputAddress)),
    'sources' : IDL.Vec(IDL.Opt(InputAddress)),
    'affiliate' : IDL.Opt(Account),
    'ledgers' : IDL.Vec(SupportedLedger),
    'temporary' : IDL.Bool,
    'refund' : Account,
  });
  const CreateRequest__1 = IDL.Record({
    'variables' : IDL.Record({
      'dissolve_delay' : DissolveDelay,
      'dissolve_status' : DissolveStatus,
      'followee' : Followee,
    }),
  });
  const CreateRequest = IDL.Variant({
    'devefi_jes1_icpneuron' : CreateRequest__1,
  });
  const CreateNodeRequest = IDL.Tuple(CommonCreateRequest, CreateRequest);
  const TransferRequest = IDL.Record({
    'to' : IDL.Variant({
      'node_billing' : LocalNodeId,
      'node' : IDL.Record({
        'node_id' : LocalNodeId,
        'endpoint_idx' : EndpointIdx,
      }),
      'external_account' : IDL.Variant({
        'ic' : Account,
        'other' : IDL.Vec(IDL.Nat8),
      }),
      'account' : Account,
    }),
    'from' : IDL.Variant({
      'node' : IDL.Record({
        'node_id' : LocalNodeId,
        'endpoint_idx' : EndpointIdx,
      }),
      'account' : Account,
    }),
    'ledger' : SupportedLedger,
    'amount' : IDL.Nat,
  });
  const Command = IDL.Variant({
    'modify_node' : ModifyNodeRequest,
    'create_node' : CreateNodeRequest,
    'transfer' : TransferRequest,
    'delete_node' : LocalNodeId,
  });
  const BatchCommandRequest = IDL.Record({
    'request_id' : IDL.Opt(IDL.Nat32),
    'controller' : Controller,
    'signature' : IDL.Opt(IDL.Vec(IDL.Nat8)),
    'expire_at' : IDL.Opt(IDL.Nat64),
    'commands' : IDL.Vec(Command),
  });
  const Activity = IDL.Variant({
    'Ok' : IDL.Record({ 'operation' : IDL.Text, 'timestamp' : IDL.Nat64 }),
    'Err' : IDL.Record({
      'msg' : IDL.Text,
      'operation' : IDL.Text,
      'timestamp' : IDL.Nat64,
    }),
  });
  const UpdatingStatus = IDL.Variant({
    'Calling' : IDL.Nat64,
    'Done' : IDL.Nat64,
    'Init' : IDL.Null,
  });
  const SharedNeuronCache = IDL.Record({
    'dissolve_delay_seconds' : IDL.Opt(IDL.Nat64),
    'maturity_e8s_equivalent' : IDL.Opt(IDL.Nat64),
    'cached_neuron_stake_e8s' : IDL.Opt(IDL.Nat64),
    'created_timestamp_seconds' : IDL.Opt(IDL.Nat64),
    'state' : IDL.Opt(IDL.Int32),
    'nonce' : IDL.Opt(IDL.Nat64),
    'followees' : IDL.Vec(
      IDL.Tuple(
        IDL.Int32,
        IDL.Record({ 'followees' : IDL.Vec(IDL.Record({ 'id' : IDL.Nat64 })) }),
      )
    ),
    'voting_power' : IDL.Opt(IDL.Nat64),
    'neuron_id' : IDL.Opt(IDL.Nat64),
    'age_seconds' : IDL.Opt(IDL.Nat64),
  });
  const Shared__1 = IDL.Record({
    'log' : IDL.Vec(Activity),
    'internals' : IDL.Record({
      'local_idx' : IDL.Nat32,
      'refresh_idx' : IDL.Opt(IDL.Nat64),
      'updating' : UpdatingStatus,
      'spawning_neurons' : IDL.Vec(SharedNeuronCache),
    }),
    'cache' : SharedNeuronCache,
    'variables' : IDL.Record({
      'dissolve_delay' : DissolveDelay,
      'dissolve_status' : DissolveStatus,
      'followee' : Followee,
    }),
  });
  const Shared = IDL.Variant({ 'devefi_jes1_icpneuron' : Shared__1 });
  const BillingTransactionFee = IDL.Variant({
    'none' : IDL.Null,
    'transaction_percentage_fee_e8s' : IDL.Nat,
    'flat_fee_multiplier' : IDL.Nat,
  });
  const EndpointOptIC = IDL.Record({
    'ledger' : IDL.Principal,
    'account' : IDL.Opt(Account),
  });
  const EndpointOptOther = IDL.Record({
    'platform' : IDL.Nat64,
    'ledger' : IDL.Vec(IDL.Nat8),
    'account' : IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  const EndpointOpt = IDL.Variant({
    'ic' : EndpointOptIC,
    'other' : EndpointOptOther,
  });
  const DestinationEndpointResp = IDL.Record({
    'endpoint' : EndpointOpt,
    'name' : IDL.Text,
  });
  const SourceEndpointResp = IDL.Record({
    'balance' : IDL.Nat,
    'endpoint' : Endpoint,
    'name' : IDL.Text,
  });
  const GetNodeResponse = IDL.Record({
    'id' : LocalNodeId,
    'created' : IDL.Nat64,
    'active' : IDL.Bool,
    'modified' : IDL.Nat64,
    'controllers' : IDL.Vec(Controller),
    'custom' : IDL.Opt(Shared),
    'extractors' : IDL.Vec(LocalNodeId),
    'billing' : IDL.Record({
      'transaction_fee' : BillingTransactionFee,
      'expires' : IDL.Opt(IDL.Nat64),
      'current_balance' : IDL.Nat,
      'billing_option' : IDL.Nat,
      'account' : Account,
      'frozen' : IDL.Bool,
      'cost_per_day' : IDL.Nat,
    }),
    'destinations' : IDL.Vec(DestinationEndpointResp),
    'sources' : IDL.Vec(SourceEndpointResp),
    'refund' : Account,
  });
  const ModifyNodeResponse = IDL.Variant({
    'ok' : GetNodeResponse,
    'err' : IDL.Text,
  });
  const CreateNodeResponse = IDL.Variant({
    'ok' : GetNodeResponse,
    'err' : IDL.Text,
  });
  const TransferResponse = IDL.Variant({ 'ok' : IDL.Nat64, 'err' : IDL.Text });
  const DeleteNodeResp = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  const CommandResponse = IDL.Variant({
    'modify_node' : ModifyNodeResponse,
    'create_node' : CreateNodeResponse,
    'transfer' : TransferResponse,
    'delete_node' : DeleteNodeResp,
  });
  const BatchCommandResponse = IDL.Variant({
    'ok' : IDL.Record({
      'id' : IDL.Opt(IDL.Nat),
      'commands' : IDL.Vec(CommandResponse),
    }),
    'err' : IDL.Variant({
      'caller_not_controller' : IDL.Null,
      'expired' : IDL.Null,
      'other' : IDL.Text,
      'duplicate' : IDL.Nat,
      'invalid_signature' : IDL.Null,
    }),
  });
  const GetControllerNodesRequest = IDL.Record({
    'id' : Controller,
    'start' : LocalNodeId,
    'length' : IDL.Nat32,
  });
  const NodeShared = IDL.Record({
    'id' : LocalNodeId,
    'created' : IDL.Nat64,
    'active' : IDL.Bool,
    'modified' : IDL.Nat64,
    'controllers' : IDL.Vec(Controller),
    'custom' : IDL.Opt(Shared),
    'extractors' : IDL.Vec(LocalNodeId),
    'billing' : IDL.Record({
      'transaction_fee' : BillingTransactionFee,
      'expires' : IDL.Opt(IDL.Nat64),
      'current_balance' : IDL.Nat,
      'billing_option' : IDL.Nat,
      'account' : Account,
      'frozen' : IDL.Bool,
      'cost_per_day' : IDL.Nat,
    }),
    'destinations' : IDL.Vec(DestinationEndpointResp),
    'sources' : IDL.Vec(SourceEndpointResp),
    'refund' : Account,
  });
  const GetNode = IDL.Variant({ 'id' : LocalNodeId, 'endpoint' : Endpoint });
  const BillingFeeSplit = IDL.Record({
    'platform' : IDL.Nat,
    'author' : IDL.Nat,
    'affiliate' : IDL.Nat,
    'pylon' : IDL.Nat,
  });
  const BillingPylon = IDL.Record({
    'operation_cost' : IDL.Nat,
    'freezing_threshold_days' : IDL.Nat,
    'min_create_balance' : IDL.Nat,
    'split' : BillingFeeSplit,
    'ledger' : IDL.Principal,
    'platform_account' : Account,
    'pylon_account' : Account,
  });
  const LedgerInfo = IDL.Record({
    'fee' : IDL.Nat,
    'decimals' : IDL.Nat8,
    'name' : IDL.Text,
    'ledger' : SupportedLedger,
    'symbol' : IDL.Text,
  });
  const Billing = IDL.Record({
    'transaction_fee' : BillingTransactionFee,
    'cost_per_day' : IDL.Nat,
  });
  const Version = IDL.Variant({
    'alpha' : IDL.Vec(IDL.Nat16),
    'beta' : IDL.Vec(IDL.Nat16),
    'release' : IDL.Vec(IDL.Nat16),
  });
  const LedgerIdx = IDL.Nat;
  const LedgerLabel = IDL.Text;
  const EndpointsDescription = IDL.Vec(IDL.Tuple(LedgerIdx, LedgerLabel));
  const ModuleMeta = IDL.Record({
    'id' : IDL.Text,
    'create_allowed' : IDL.Bool,
    'ledger_slots' : IDL.Vec(IDL.Text),
    'name' : IDL.Text,
    'billing' : IDL.Vec(Billing),
    'description' : IDL.Text,
    'supported_ledgers' : IDL.Vec(SupportedLedger),
    'author' : IDL.Text,
    'version' : Version,
    'destinations' : EndpointsDescription,
    'sources' : EndpointsDescription,
    'temporary_allowed' : IDL.Bool,
    'author_account' : Account,
  });
  const PylonMetaResp = IDL.Record({
    'name' : IDL.Text,
    'billing' : BillingPylon,
    'supported_ledgers' : IDL.Vec(LedgerInfo),
    'request_max_expire_sec' : IDL.Nat64,
    'governed_by' : IDL.Text,
    'temporary_nodes' : IDL.Record({
      'allowed' : IDL.Bool,
      'expire_sec' : IDL.Nat64,
    }),
    'modules' : IDL.Vec(ModuleMeta),
  });
  const NNSVECTOR = IDL.Service({
    'get_ledger_errors' : IDL.Func([], [IDL.Vec(IDL.Vec(IDL.Text))], ['query']),
    'get_ledgers_info' : IDL.Func([], [IDL.Vec(LedgerInfo__1)], ['query']),
    'icrc3_get_archives' : IDL.Func(
        [GetArchivesArgs],
        [GetArchivesResult],
        ['query'],
      ),
    'icrc3_get_blocks' : IDL.Func(
        [GetBlocksArgs],
        [GetBlocksResult],
        ['query'],
      ),
    'icrc3_get_tip_certificate' : IDL.Func(
        [],
        [IDL.Opt(DataCertificate)],
        ['query'],
      ),
    'icrc3_supported_block_types' : IDL.Func(
        [],
        [IDL.Vec(BlockType)],
        ['query'],
      ),
    'icrc55_account_register' : IDL.Func([Account], [], []),
    'icrc55_accounts' : IDL.Func(
        [AccountsRequest],
        [AccountsResponse],
        ['query'],
      ),
    'icrc55_command' : IDL.Func(
        [BatchCommandRequest],
        [BatchCommandResponse],
        [],
      ),
    'icrc55_get_controller_nodes' : IDL.Func(
        [GetControllerNodesRequest],
        [IDL.Vec(NodeShared)],
        ['query'],
      ),
    'icrc55_get_defaults' : IDL.Func([IDL.Text], [CreateRequest], ['query']),
    'icrc55_get_nodes' : IDL.Func(
        [IDL.Vec(GetNode)],
        [IDL.Vec(IDL.Opt(NodeShared))],
        ['query'],
      ),
    'icrc55_get_pylon_meta' : IDL.Func([], [PylonMetaResp], ['query']),
  });
  return NNSVECTOR;
};
export const init = ({ IDL }) => { return []; };
