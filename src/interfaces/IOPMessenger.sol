// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOPMessenger {
    function xDomainMessageSender() external returns (address);

    function bridgeERC20To(
        address localToken,
        address remoteToken,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    )
        external;

    function sendMessage(address target, bytes memory message, uint32 gasLimit) external payable;
}
