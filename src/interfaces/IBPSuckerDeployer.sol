// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSucker} from "./IBPSucker.sol";

interface IBPSuckerDeployer {
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IBPSucker sucker);
}
