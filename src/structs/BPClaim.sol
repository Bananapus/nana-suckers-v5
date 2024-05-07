// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BPLeaf} from "./BPLeaf.sol";

struct BPClaim {
    address token;
    uint64 remoteSelector;
    BPLeaf leaf;
    // Must be `BPSucker.TREE_DEPTH` long.
    bytes32[32] proof;
}
