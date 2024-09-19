dfx canister --network ic stop nns_vector
dfx deploy --network ic nns_vector
dfx canister --network ic start nns_vector
dfx canister --network ic call nns_vector start