import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface CanisterInfo { 'cycles' : bigint }
export type GetSlicesResp = Array<[Principal, number, number]>;
export type SetAccessRequest = Array<[Principal, string]>;
export interface _SERVICE {
  'canister_info' : ActorMethod<[], CanisterInfo>,
  'get_slices' : ActorMethod<[], GetSlicesResp>,
  'set_access' : ActorMethod<[SetAccessRequest], undefined>,
  'show_log' : ActorMethod<[], Array<[] | [string]>>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
