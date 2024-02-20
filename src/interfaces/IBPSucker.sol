// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {BPTokenMapping} from "../structs/BPTokenMapping.sol";

interface IBPSucker {
    function isMapped(address token) external view returns (bool);

    function prepare(uint256 projectTokenAmount, address beneficiary, uint256 minTokensReclaimed, address token)
        external;

    function mapToken(BPTokenMapping calldata map) external payable;

    function mapTokens(BPTokenMapping[] calldata maps) external payable;
}