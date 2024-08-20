// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import {IArbGatewayRouter} from "./IArbGatewayRouter.sol";
import {JBLayer} from "./../enums/JBLayer.sol";

interface IJBArbitrumSucker {
    function ARBINBOX() external view returns (IInbox);
    function GATEWAYROUTER() external view returns (IArbGatewayRouter);
    function LAYER() external view returns (JBLayer);
}
