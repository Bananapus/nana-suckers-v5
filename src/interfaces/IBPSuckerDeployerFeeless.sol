// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "./IBPSuckerDeployer.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPayoutTerminal.sol";

interface IBPSuckerDeployerFeeless is IBPSuckerDeployer {
    /// @notice Use the allowance of a project witgout paying exit fees.
    /// @dev This function can only be called by suckers deployed by this contract, and only if the project owner has given the specicifc sucker permission to use the allowance.
    /// @dev This is not necesarily feeless, as it still requires JBDAO to mark this as feeless first.
    /// @param _projectId the project id.
    /// @param _terminal the terminal to use.
    /// @param _token the token to use the allowance of.
    /// @param _currency the currency the amount is denominated in.
    /// @param _amount the amount to get from the terminal, denomated in the currency.
    /// @param _minReceivedTokens the minimum amount of tokens to receive.
    /// @return the amount of tokens received.
    function useAllowanceFeeless(
        uint256 _projectId,
        IJBPayoutTerminal _terminal,
        address _token,
        uint32 _currency,
        uint256 _amount,
        uint256 _minReceivedTokens
    ) external returns (uint256);
}
