// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface OPMessenger {
    function xDomainMessageSender() external returns (address);

    function sendMessage(address _target, bytes memory _message, uint32 _gasLimit) external payable;

    function bridgeERC20To(
        address localToken,
        address remoteToken,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external;
}
