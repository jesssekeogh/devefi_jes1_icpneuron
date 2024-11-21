# DeVeFi ICP Neuron Vector

The devefi ICP neuron vector is a module that can be plugged into pylons that run the DeVeFi framework. This package will only work within the context of a pylon system and the ICRC-55 standard.

The naming of modules within the devefi framework follow the `devefi` _ `<author>` _ `<module>` naming convention.

## Running the tests
This repository includes a compressed copy of the `nns_state`, which is decompressed during the npm install process via the postinstall script. The script uses command `tar -xvf ./state/nns_state.tar.xz -C ./` to extract the file. The tests use multiple canisters along with the library to perform operations such as creating nodes, staking neurons, spawning maturity and simulating the passage of significant time. As a result, the tests may take a while to complete.

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