// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPayoutTerminal.sol";

interface FeelessDeployer {
    function useAllowanceFeeless(
        uint256 _projectId,
        IJBPayoutTerminal _terminal,
        address _token,
        uint32 _currency,
        uint256 _amount,
        uint256 _minReceivedTokens
    ) external returns (uint256);
}
