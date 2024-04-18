// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Common interface for L1 and L2 Gateway Routers
 */
interface IArbGatewayRouter {
    function defaultGateway() external view returns (address gateway);

    function getGateway(address _token) external view returns (address gateway);
}
