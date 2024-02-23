// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSucker} from "./IBPSucker.sol";

interface IBPSuckerDeployer {
    /// @notice Create a new sucker for a specific project.
    /// @dev uses the sender address as the salt, requires the same sender to deploy on both chains.
    /// @param _localProjectId the project id on this chain.
    /// @param _salt the salt to use for the create2 address.
    /// @return _sucker the address of the new sucker.
    function createForSender(uint256 _localProjectId, bytes32 _salt) external returns (IBPSucker _sucker);
}
