// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "./IBPSuckerDeployer.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";

interface IBPSuckerDeployerFeeless is IBPSuckerDeployer {
    function useAllowanceFeeless(
        uint256 projectId,
        IJBPayoutTerminal terminal,
        address token,
        uint32 currency,
        uint256 amount,
        uint256 minReceivedTokens
    ) external returns (uint256);
}
