# BPSucker

`BPSucker.sol` facilitates cross-chain token transfers between projects, using a messenger for communication and a redemption mechanism for token exchange. `BPSucker` only works with Optimism for now.

- `BPSucker` maintains a mapping `acceptFromRemote` that links local project IDs to their corresponding remote project IDs.
- `BPSucker`'s main external functions are:
  - `register`: This function registers a remote project ID as the peer of a local project ID. It requires the caller to have the appropriate permissions.
  - `toRemote`: Send tokens from a local project to a remote project. It first checks if the remote project is valid, then redeems the tokens at the local terminal, and finally sends a message to the peer contract on the remote chain with the redeemed ETH.
  - `fromRemote`: This function receives tokens from a remote project. It checks if the message came from the peer contract and if the remote project is valid, then adds the redeemed funds to the local terminal and mints tokens for the beneficiary.

## Usage

You must have [Foundry](https://book.getfoundry.sh/) and [NodeJS](https://nodejs.dev/en/learn/how-to-install-nodejs/) to use this repo.

Install with `forge install`

If you run into trouble with nested dependencies, try running `git submodule update --init --force --recursive`.

```shell
$ forge build # Build
$ forge test # Run tests
$ forge fmt # Format
$ forge snapshot # Gas Snapshots
```

For help, see https://book.getfoundry.sh/ or run:

```shell
$ forge --help
$ anvil --help
$ cast --help
```
