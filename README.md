# DeVeFi ICP Neuron Vector
The DeVeFi ICP Neuron Vector is a module that can be integrated into pylons running the DeVeFi framework. This package operates within the context of a pylon system and the ICRC-55 standard. Modules within the DeVeFi framework follow the naming convention: `devefi` _ `<author>` _ `<module>`.

Note: This README assumes familiarity with ICP, the Network Nervous System (NNS), and neurons. Not all neuron concepts are explained in detail.

## Create ICP Neuron Vectors

This module integrates with pylons—canisters running the DeVeFi framework and governed by SNS DAOs on the ICP network—enabling users to create instances of ICP neuron vectors. To create the vector, a minimum creation fee is required, charged by the pylon. For example, the Neutrinite DAO pylons may charge a creation fee of 2 NTN, which is stored in the vector's billing account. By default, each vector includes configurable options such as destinations, sources, billing, and refund settings, among other features. 

Alongside these standard vector configurations, **the ICP neuron vector enables the pylon to stake neurons on behalf of vector owners while granting them control over the neuron.** The pylon achieves this by making calls to the Network Nervous System (NNS).

## Vector Source Accounts

When you create an ICP neuron vector, you receive two non-configurable source accounts (one is hidden):

**"Stake" source** 

This ICRC-1 account accepts ICP tokens. Once you reach the minimum stake threshold (currently 20 ICP), it automatically forwards the tokens to a newly created neuron subaccount owned by your vector. The module then stakes a new neuron on your behalf and stores its data in your vector. You can increase your stake by sending any amount above the ICP transaction fee to the vector's "Stake" source again.

**"_Maturity" source**

This hidden ICRC-1 account is used internally to forward your ICP maturity to your destination account. Any disbursed maturity is routed here first before being forwarded to your destination.

## Vector Destination Accounts

When you create an ICP neuron vector, you are provided with two configurable destination accounts, which can be updated at any time. Both destinations can be external accounts or other vectors:

**"Maturity" destination**

The ICRC-1 account where your claimed ICP maturity rewards are sent.

**"Disburse" destination**

The ICRC-1 account that will receive the ICP staked in your main neuron if it is dissolved.


## Multiple Neurons

The neuron initially staked by the vector is called the main neuron (or `cache` internally). A single vector can also control additional split neurons (or `neuron_cache` internally). Each neuron managed by your vector has its own deterministic subaccount that encodes the pylon canister ID, your vector ID, a local neuron index, and a domain tag such as "neuron-stake" or "split-neuron." This structure makes every neuron fully traceable and allows your vector to safely manage multiple neurons, which is essential for advanced protocols and voting systems.


**Configure your neurons**

The neurons can be configured by the vector controller. The available configurations are:
```javascript
'variables': {
    'dissolve_delay': { 'Default': null } | { 'DelayDays': bigint },
    'dissolve_status': { 'Locked': null } | { 'Dissolving': null },
    'followee': { 'None' : null } | { 'Default': null } | { 'FolloweeId': bigint },
    'hotkey': { 'None' : null } | { 'HotkeyId' : Principal },
    'visibility': { 'Private' : null } | { 'Public' : null },
},
```

- dissolve_delay: Setting this to Default locks the neuron for the minimum period required to earn maturity (currently 6 months). You can specify a custom duration up to 8 years using DelayDays. Values below 6 months round up to 6 months; above 8 years cap at 8 years. You can only increase (never decrease) the dissolve_delay while the neuron is Locked, and increases must be at least 7 days.

- dissolve_status: Toggles the neuron between Locked and Dissolving. The neuron can only be disbursed after it is set to Dissolving and the full dissolve_delay has elapsed. You can only increase dissolve_delay while Locked.

- followee: Controls following across all NNS proposal topics. None clears any followee, Default uses a developer-selected neuron, FolloweeId sets an explicit neuron ID to follow.

- hotkey: Assigns an optional hotkey principal that can submit proposals and vote with the neuron's voting power. None removes any existing hotkey. Hotkeys do not gain control over staking, disbursing, or configuration — only voting/proposing.

- visibility: Controls access to neuron voting history. Private (default) restricts reads. Public allows any caller to inspect and audit the neuron's voting behavior for transparency.

When you create the vector you can (and usually should) set: maturity destination, disburse destination, billing option (5% maturity or NTN daily), and any initial neuron variables (dissolve_delay, dissolve_status, followee, hotkey, visibility). After creation, any configuration change you submit is propagated to every neuron the vector manages (main + future split neurons). Typical flow:
1. Create the vector with desired destinations, billing mode, and (optionally) initial neuron configuration.
2. Fund the Stake source until the 20 ICP minimum is reached; the main neuron is then created, staked, and recorded in the vector.
3. (Optional, anytime) Adjust dissolve_delay, dissolve_status, followee, hotkey, visibility; changes apply uniformly.
4. Let maturity accrue. Once at least 1 ICP of spawnable maturity exists (after the NNS daily settlement), the vector can automatically spawn, claim, and forward rewards to the configured Maturity destination.
5. Add more ICP to the Stake source at any time to increase voting power and future reward flow.

## Billing

To cover operational costs and reward the pylon, author, platform, and affiliates, the module and pylon charge a fee. Users can choose between two billing options:

- 5% of all maturity claimed
- 3.17 NTN tokens per day

The 5% maturity fee is recommended for most users and DAOs, ensuring uninterrupted operation of their ICP neuron vector without requiring active token management.

For users opting for the NTN billing option, caution is advised: the tokens are charged from the vector's billing account. Users must ensure their account maintains a sufficient balance to cover the fee well into the future. Insufficient funds may result in the vector freezing and potential deletion. This option should be chosen only if users are confident in their ability to sustain the NTN balance.

## Use Cases

The ICP neuron vector provides an easy-to-configure, automated neuron staking experience, allowing DAOs, organizations, and teams to stake neurons on the NNS without manual setup or manual maturity disbursal through a UI. In just a few proposals, a DAO can establish an ICP neuron. Maturity rewards are automatically sent to the configured destination account. The neuron's stake can be increased at any time by sending additional ICP to the vector's Stake source account.

Additional use cases include trading systems that stake ICP and route maturity to acquire specific tokens, as well as vector-backed liquid staking protocols with advanced voting logic. The ICP neuron vector can also integrate with other vectors (e.g., throttle, splitting, liquidity), enabling composable governance and reward flows. These patterns extend far beyond what is possible with simple canister-based or UI-only staking.

## Running the Tests

This repository includes a compressed copy of the `nns_state`, which is decompressed during the npm install process via the postinstall script. The script uses command `tar -xvf ./state/nns_state.tar.xz -C ./` to extract the file. The tests use multiple canisters along with the module to perform operations such as creating nodes, staking neurons, spawning maturity and simulating the passage of significant time. As a result, the tests may take a while to complete.

The `maxWorkers` option in `jest.config.ts` is set to `1`. If your computer has sufficient resources, you can remove this restriction to run the tests in parallel.

These instructions have been tested on macOS. Ensure that the necessary CLI tools (e.g., git, npm) are installed before proceeding.

```bash
# clone the repo
git clone https://github.com/jesssekeogh/devefi_jes1_icpneuron.git

# change directory
cd devefi_jes1_icpneuron/tests/pic

# install the required packages
npm install

# run the tests
npx jest
```

## License

*To be decided*