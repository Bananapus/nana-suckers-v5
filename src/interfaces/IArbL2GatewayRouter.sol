// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbL2GatewayRouter {
    function outboundTransfer(address l1Token, address to, uint256 amount, bytes calldata data)
        external
        payable
        returns (bytes memory);
}
