// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {OPMessenger} from "../../src/interfaces/OPMessenger.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockMessenger is OPMessenger {
    address public xDomainMessageSender;

    mapping(address _localToken => address _remoteToken) tokens;

    function sendMessage(address _target, bytes memory _message, uint32 _gasLimit) external payable {
        // Update the sender
        xDomainMessageSender = msg.sender;
        // Perform the 'crosschain' call
        (bool _success,) = _target.call{value: msg.value, gas: _gasLimit}(_message);
        require(_success);
    }

    function bridgeERC20To(
        address localToken,
        address remoteToken,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external {
        // TODO: implement mock.
        assert(tokens[localToken] == remoteToken);
        // Mint the 'L1' tokens to the recipient.
        ERC20Mock(remoteToken).mint(to, amount);
    }


    function setRemoteToken(
        address localToken,
        address remoteToken
    ) external {
        tokens[localToken] = remoteToken;
    }
}
