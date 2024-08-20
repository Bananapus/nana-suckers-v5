// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Global constants used across Juicebox sucker contracts.
library JBSuckerConstants {
    /// @notice The depth of the merkle tree used to track beneficiaries, token balances, and redemption values.
    uint256 internal constant TREE_DEPTH = 32;
}
