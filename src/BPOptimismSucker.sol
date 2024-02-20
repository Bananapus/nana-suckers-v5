// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./BPSucker.sol";
import "./BPSuckerDelegate.sol";

import {OPMessenger} from "./interfaces/OPMessenger.sol";
import {OPStandardBridge} from "./interfaces/OPStandardBridge.sol";

/// @notice A contract that sucks tokens from one chain to another.
/// @dev This implementation is designed to be deployed on two chains that are connected by an OP bridge.
contract BPOptimismSucker is BPSucker, BPSuckerDelegate {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    event SuckingToRemote(address token, uint64 nonce);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The messenger in use to send messages between the local and remote sucker.
    OPMessenger public immutable OPMESSENGER;

    OPStandardBridge public immutable OPBRIDGE;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        IJBPrices _prices,
        IJBRulesets _rulesets,
        OPMessenger _messenger,
        OPStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions,
        address _peer,
        uint256 _projectId
    ) BPSucker(_directory, _tokens, _permissions, _peer, _projectId) BPSuckerDelegate(_prices, _rulesets) {
        OPMESSENGER = _messenger;
        OPBRIDGE = _bridge;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice uses the OPMESSENGER to send the root and assets over the bridge to the peer.
    /// @param _token the token to bridge for.
    /// @param _tokenConfig the config for the token to send.
    function _sendRoot(address _token, BPRemoteTokenConfig memory _tokenConfig) internal override {
        uint256 _nativeValue;

        // The OP bridge does not expect to be paid.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        // Get the amount to send and then clear it.
        uint256 _amount = outbox[_token].balance;
        delete outbox[_token].balance;

        // Increment the nonce.
        uint64 _nonce = ++outbox[_token].nonce;

        if (_tokenConfig.remoteToken == address(0)) {
            revert TOKEN_NOT_MAPPED(_token);
        }

        if (_token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(_token), address(OPBRIDGE), _amount);

            // Bridge the tokens to the payer address.
            OPBRIDGE.bridgeERC20To({
                localToken: _token,
                remoteToken: _tokenConfig.remoteToken,
                to: PEER,
                amount: _amount,
                minGasLimit: _tokenConfig.minGas,
                extraData: bytes("")
            });
        } else {
            _nativeValue = _amount;
        }

        // Send the messenger to the peer with the redeemed ETH.
        OPMESSENGER.sendMessage{value: _nativeValue}(
            PEER,
            abi.encodeCall(
                BPSucker.fromRemote,
                (
                    MessageRoot({
                        token: _tokenConfig.remoteToken,
                        amount: _amount,
                        remoteRoot: InboxTreeRoot({nonce: _nonce, root: outbox[_token].tree.root()})
                    })
                )
            ),
            MESSENGER_BASE_GAS_LIMIT
        );

        // Emit an event for the relayers to watch for.
        emit SuckingToRemote(_token, _nonce);
    }

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer.
    /// @param _sender the message sender.
    function _isRemotePeer(address _sender) internal override returns (bool _valid) {
        return _sender == address(OPMESSENGER) && OPMESSENGER.xDomainMessageSender() == PEER;
    }
}
