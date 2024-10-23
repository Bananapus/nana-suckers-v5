// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSucker, JBClaim} from "./IJBSucker.sol";

// @notice Contains the IJBSucker interface and extends it with additional functions and events.
interface IJBSuckerExtended is IJBSucker {
    event EmergencyHatchOpened(address[] tokens, address caller);
    event DeprecationTimeUpdated(uint40 timestamp, address caller);

    function enableEmergencyHatchFor(address[] calldata tokens) external;
    function exitThroughEmergencyHatch(JBClaim calldata claimData) external;
    function setDeprecation(uint40 timestamp) external;
}
