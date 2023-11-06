// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BPSuckQueueItem} from "./BPSuckQueueItem.sol";

struct BPSuckerData {
    uint256 redemptionAmount;
    BPSuckQueueItem[] items;
}
