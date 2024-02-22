// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A leaf in the inbox or outbox tree of a `BPSucker`. Used to `claim` tokens from the inbox tree.
struct BPLeaf {
    uint256 index;
    address beneficiary;
    uint256 projectTokenAmount;
    uint256 terminalTokenAmount;
}
