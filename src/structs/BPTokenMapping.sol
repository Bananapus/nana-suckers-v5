// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct BPTokenMapping {
    address localToken;
    uint32 minGas;
    address remoteToken;
    uint256 minBridgeAmount;
}
