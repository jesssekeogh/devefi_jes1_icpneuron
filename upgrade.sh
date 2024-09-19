dfx canister --network ic stop devefi_staking
dfx deploy --network ic devefi_staking
dfx canister --network ic start devefi_staking
dfx canister --network ic call devefi_staking start