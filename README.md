# DeVeFi ICP Neuron Vector
The DeVeFi ICP Neuron Vector is a module that can be integrated into pylons running the DeVeFi framework. This package operates within the context of a pylon system and the ICRC-55 standard. Modules within the DeVeFi framework follow the naming convention: `devefi` _ `<author>` _ `<module>`.

Note: This README assumes familiarity with ICP, the Network Nervous System (NNS), and neurons. Not all neuron concepts are explained in detail.

## Create ICP Neuron Vectors

This module integrates with pylons—canisters running the DeVeFi framework and governed by SNS DAOs on the ICP network—enabling users to create instances of ICP neuron vectors. To create the vector, a minimum creation fee is required, charged by the pylon. For example, the Neutrinite DAO pylons may charge a creation fee of 0.5 NTN, which is stored in the vector's billing account. By default, each vector includes configurable options such as destinations, sources, billing, and refund settings, among other features. 

Alongside these standard vector configurations, **the ICP neuron vector enables the pylon to stake neurons on behalf of vector owners while granting them control over the neuron.** The pylon achieves this by making calls to the Network Nervous System (NNS).

## Vector Source Accounts

When you create an ICP neuron vector, you receive two non-configurable source accounts (one is hidden):

**"Stake" source** 

This ICRC-1 account accepts ICP tokens. Once you reach the minimum stake threshold (currently 20 ICP), it automatically forwards the tokens to a newly created neuron subaccount owned by your vector. The module then stakes a new neuron on your behalf and stores its data in your vector. You can increase your stake by sending any amount above the ICP transaction fee to the vector's "Stake" source again.

**"_Maturity" source**

This hidden ICRC-1 account is used internally to forward your ICP maturity to your destination account. Any maturity claimed from spawned neurons is routed here first before being forwarded to your destination.

## Vector Destination Accounts

When you create an ICP neuron vector, you are provided with two configurable destination accounts, which can be updated at any time. Both destinations can be external accounts or other vectors:

**"Maturity" destination**

The ICRC-1 account where your claimed ICP maturity rewards are sent.

**"Disburse" destination**

The ICRC-1 account that will receive the ICP staked in your main neuron when it is dissolved.


## The Main Neuron

The staked neuron within the vector is referred to as the main neuron. When you spawn maturity, additional neurons—called spawning neurons—are created and also tracked in your vector's memory. All neurons controlled by your vector have a unique subaccount that includes the pylon's canister ID, your vector's ID, and a local vector ID. This ensures that your vector's neurons are fully traceable and allows your vector to own multiple neurons, which is necessary when spawning numerous maturity neurons.


**Configure your main neuron**

The main neuron can be configured by the vector controller, allowing you to maintain voting power and earn rewards. The available configurations are:

```javascript
'variables': {
    'dissolve_delay': { 'Default': null } | { 'DelayDays': bigint },
    'dissolve_status': { 'Locked': null } | { 'Dissolving': null },
    'followee': { 'Default': null } | { 'FolloweeId': bigint },
},
```

- `dissolve_delay`: Setting this to `Default` locks the neuron for the minimum period required to earn maturity—currently 6 months. You can specify a custom duration up to 8 years using `DelayDays`. If you set `DelayDays` below 6 months, it defaults to 6 months; if above 8 years, it defaults to 8 years. You can increase the `dissolve_delay` later (by at least 1 week) if the neuron is in the `Locked` state.

- `dissolve_status`: Switches your neuron's state between `Locked` and `Dissolving`. The neuron can only be disbursed if it's set to `Dissolving` and the dissolve delay has elapsed. The `dissolve_delay` can only be increased when the neuron is in the `Locked` state.

- `followee`: Determines which neuron your main neuron follows for voting on NNS proposals. It follows the specified neuron on all proposal topics. A `Default` option is provided (a neuron chosen by the developers), but it's recommended to select a specific `FolloweeId` (an NNS neuron ID) of your choice.

## Maturity Automation

An ICP neuron vector can spawn and control multiple spawning neurons with maturity. When a spawning neuron is ready to be claimed, its maturity is sent to your custom destination account. This process is entirely automatic—you can create and configure your main neuron and watch as ICP is sent to your destination account once enough maturity has accumulated to spawn (minimum of 1 ICP). The more ICP you stake, the faster you accrue maturity and ICP rewards are sent to the destination. Note that the NNS disburses maturity once per day, so vectors can spawn at most one neuron daily.

## Billing

To cover operational costs and reward the pylon, author, platform, and affiliates, the module and pylon charge a fee. Users can choose between two billing options:

- 5% of all maturity claimed
- 3.17 NTN tokens per day

The 5% maturity fee is recommended for most users and DAOs, ensuring uninterrupted operation of their ICP neuron vector without requiring active token management.

For users opting for the NTN billing option, caution is advised: the tokens are charged from the vector's billing account. Users must ensure their account maintains a sufficient balance to cover the fee well into the future. Insufficient funds may result in the vector freezing and potential deletion. This option should be chosen only if users are confident in their ability to sustain the NTN balance.

## Use Cases

The ICP neuron vector offers an easy-to-configure and automated neuron staking experience, simplifying the process for DAOs, organizations, and teams to stake neurons on the NNS without manual configurations, spawning, or claiming via a UI. Maturity rewards are automatically sent to your chosen destination account. The neurons stake can also be easily increased by sending additional ICP tokens to the vectors stake source account.

Additional use cases include trading systems that stake ICP and use the maturity rewards to purchase specific tokens. The ICP neuron vector can also interact with the broader ecosystem of vectors and integrate with throttle, splitting and liquidity vectors. The possibilities are extensive and surpass what is achievable with simple canister staking or UI-based staking.

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