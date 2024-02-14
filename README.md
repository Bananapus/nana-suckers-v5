# Bananapus Sucker

`BPSucker.sol` facilitates cross-chain token transfers between projects, using a messenger for communication and a redemption mechanism for token exchange. `BPSucker` only works with Optimism for now.

- `BPSucker` maintains a mapping `acceptFromRemote` that links local project IDs to their corresponding remote project IDs.
- `BPSucker`'s main external functions are:
  - `register`: This function registers a remote project ID as the peer of a local project ID. It requires the caller to have the appropriate permissions.
  - `toRemote`: Send tokens from a local project to a remote project. It first checks if the remote project is valid, then redeems the tokens at the local terminal, and finally sends a message to the peer contract on the remote chain with the redeemed ETH.
  - `fromRemote`: This function receives tokens from a remote project. It checks if the message came from the peer contract and if the remote project is valid, then adds the redeemed funds to the local terminal and mints tokens for the beneficiary.

## Install

For `npm` projects (recommended):

```bash
npm install @bananapus/sucker
```

For `forge` projects (not recommended):

```bash
forge install Bananapus/nana-sucker
```

Add `@bananapus/sucker/=lib/nana-sucker/` to `remappings.txt`. You'll also need to install `nana-sucker`'s dependencies and add similar remappings for them.

## Develop

`nana-sucker` uses [yarn](https://yarnpkg.com/) for package management and the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, [install yarn](https://yarnpkg.com/getting-started/install) and install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
yarn install && forge install
```

If you run into trouble with `forge install`, try using `git submodule update --init --recursive` to ensure that nested submodules have been properly initialized.

Some useful commands:

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `forge build`         | Compile the contracts and write artifacts to `out`. |
| `forge fmt`           | Lint.                                               |
| `forge test`          | Run the tests.                                      |
| `forge build --sizes` | Get contract sizes.                                 |
| `forge coverage`      | Generate a test coverage report.                    |
| `foundryup`           | Update foundry. Run this periodically.              |
| `forge clean`         | Remove the build artifacts and cache directories.   |

To learn more, visit the [Foundry Book](https://book.getfoundry.sh/) docs.

## Scripts

For convenience, several utility commands are available in `package.json`.

| Command                        | Description                            |
| ------------------------------ | -------------------------------------- |
| `yarn test`                    | Run local tests.                       |
| `yarn coverage`                | Generate an LCOV test coverage report. |
| `yarn deploy:ethereum-mainnet` | Deploy to Ethereum mainnet             |
| `yarn deploy:ethereum-sepolia` | Deploy to Ethereum Sepolia testnet     |
| `yarn deploy:optimism-mainnet` | Deploy to Optimism mainnet             |
| `yarn deploy:optimism-testnet` | Deploy to Optimism testnet             |
