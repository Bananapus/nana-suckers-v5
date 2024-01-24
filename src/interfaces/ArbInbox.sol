// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

interface ArbInbox {
    function bridge() external view returns (IBridge);
}
