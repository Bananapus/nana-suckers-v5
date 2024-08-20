// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {JBLayer} from "../enums/JBLayer.sol";

interface IJBArbitrumSuckerDeployer {
    function LAYER() external view returns (JBLayer);
}