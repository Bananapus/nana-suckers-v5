// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbL1GatewayRouter {
    function outboundTransferCustomRefund(
        address token,
        address refundTo,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory);
}
