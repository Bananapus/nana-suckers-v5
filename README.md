# Bananapus Sucker

`BPSucker.sol` facilitates cross-chain token transfers between projects, using a messenger for communication and a redemption mechanism for token exchange. `BPSucker` only works with Optimism for now.

- `BPSucker` maintains a mapping `acceptFromRemote` that links local project IDs to their corresponding remote project IDs.
- `BPSucker`'s main external functions are:
  - `register`: This function registers a remote project ID as the peer of a local project ID. It requires the caller to have the appropriate permissions.
  - `toRemote`: Send tokens from a local project to a remote project. It first checks if the remote project is valid, then redeems the tokens at the local terminal, and finally sends a message to the peer contract on the remote chain with the redeemed ETH.
  - `fromRemote`: This function receives tokens from a remote project. It checks if the message came from the peer contract and if the remote project is valid, then adds the redeemed funds to the local terminal and mints tokens for the beneficiary.

_If you're having trouble understanding this contract, take a look at the [core protocol contracts](https://github.com/Bananapus/nana-core) and the [documentation](https://docs.juicebox.money/) first. If you have questions, reach out on [Discord](https://discord.com/invite/ErQYmth4dS)._

## Install

For `npm` projects (recommended):

```bash
npm install @bananapus/suckers
```

For `forge` projects (not recommended):

```bash
forge install Bananapus/nana-suckers
```

Add `@bananapus/suckers/=lib/nana-suckers/` to `remappings.txt`. You'll also need to install `nana-suckers`' dependencies and add similar remappings for them.

## Develop

`nana-suckers` uses [npm](https://www.npmjs.com/) for package management and the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, [install Node.js](https://nodejs.org/en/download) and install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
npm install && forge install
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

| Command                           | Description                            |
| --------------------------------- | -------------------------------------- |
| `npm test`                        | Run local tests.                       |
| `npm run coverage`                | Generate an LCOV test coverage report. |
| `npm run deploy:ethereum-mainnet` | Deploy to Ethereum mainnet             |
| `npm run deploy:ethereum-sepolia` | Deploy to Ethereum Sepolia testnet     |
| `npm run deploy:optimism-mainnet` | Deploy to Optimism mainnet             |
| `npm run deploy:optimism-testnet` | Deploy to Optimism testnet             |
