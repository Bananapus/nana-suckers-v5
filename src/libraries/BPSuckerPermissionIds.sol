// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Permission IDs for `JBPermissions`. These grant permissions scoped to `BPSucker`s.
library BPSuckerPermissionIds {
    // 1-20 - `JBPermissionIds`
    // 21 - `JBHandlePermissionIds`
    // 22-24 - `JB721PermissionIds`
    // 25-26 - `JBBuybackPermissionIds`
    // 27-28 - `JBSwapTerminalPermissionIds`
    uint256 public constant MAP_TOKEN = 29;
}
