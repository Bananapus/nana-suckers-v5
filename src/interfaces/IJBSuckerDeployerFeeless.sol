// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSuckerDeployer} from "./IJBSuckerDeployer.sol";
import {IJBPayoutTerminal} from "@bananapus/core-v5/src/interfaces/IJBPayoutTerminal.sol";

interface IJBSuckerDeployerFeeless is IJBSuckerDeployer {
    function useAllowanceFeeless(
        uint256 projectId,
        IJBPayoutTerminal terminal,
        address token,
        uint32 currency,
        uint256 amount,
        uint256 minTokensReclaimed
    )
        external
        returns (uint256);
}
