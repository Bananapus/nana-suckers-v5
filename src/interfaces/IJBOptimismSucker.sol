// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOPMessenger} from "./IOPMessenger.sol";
import {IOPStandardBridge} from "./IOPStandardBridge.sol";

interface IJBOptimismSucker {
    function OPBRIDGE() external view returns (IOPStandardBridge);
    function OPMESSENGER() external view returns (IOPMessenger);
}
