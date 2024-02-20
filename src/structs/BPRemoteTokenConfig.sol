// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

struct BPRemoteTokenConfig {
    uint32 minGas;
    address remoteToken;
    uint256 minBridgeAmount;
}
