// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSucker} from "./IJBSucker.sol";
import {ICCIPRouter} from "./ICCIPRouter.sol";

interface IJBCCIPSuckerDeployer {
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker);

    function remoteChainId() external view returns (uint256);

    function remoteChainSelector() external view returns (uint64);

    function ccipRouter() external view returns (ICCIPRouter);
}
