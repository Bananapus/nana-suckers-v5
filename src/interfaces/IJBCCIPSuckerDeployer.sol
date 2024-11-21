// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSucker} from "./IJBSucker.sol";
import {ICCIPRouter} from "./ICCIPRouter.sol";

interface IJBCCIPSuckerDeployer {
    event CCIPConstantsSet(
        address ccipRouter, 
        uint256 ccipRemoteChainId, 
        uint64 ccipRemoteChainSelector, 
        address caller
    );

    function ccipRouter() external view returns (ICCIPRouter);
    function ccipRemoteChainId() external view returns (uint256);
    function ccipRemoteChainSelector() external view returns (uint64);
}
