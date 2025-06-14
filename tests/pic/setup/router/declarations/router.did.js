export const idlFactory = ({ IDL }) => {
  const CanisterInfo = IDL.Record({ 'cycles' : IDL.Nat });
  const GetSlicesResp = IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Nat32, IDL.Nat32));
  const SetAccessRequest = IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Text));
  return IDL.Service({
    'canister_info' : IDL.Func([], [CanisterInfo], ['query']),
    'get_slices' : IDL.Func([], [GetSlicesResp], ['query']),
    'set_access' : IDL.Func([SetAccessRequest], [], []),
    'show_log' : IDL.Func([], [IDL.Vec(IDL.Opt(IDL.Text))], ['query']),
  });
};
export const init = ({ IDL }) => { return []; };
