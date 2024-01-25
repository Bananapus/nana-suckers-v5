// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

import "./BPSucker.sol";


/// @notice A contract that sucks tokens from one chain to another.
/// @dev This implementation is designed to be deployed on two chains that are connected by an OP bridge.
contract BPArbitrumSucker is BPSucker {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    enum Layer {
        L1,
        L2
    }

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    Layer public immutable LAYER;

    IInbox public immutable INBOX;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        Layer _layer,
        address _inbox,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions,
        address _peer,
        uint256 _projectId
    ) BPSucker(_directory, _tokens, _permissions, _peer, _projectId) {
        LAYER = _layer;
        INBOX = IInbox(_inbox);
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice uses the OPMESSENGER to send the root and assets over the bridge to the peer.
    /// @param _token the token to bridge for.
    /// @param _tokenConfig the config for the token to send.
    function _sendRoot(
        address _token,
        BPTokenConfig memory _tokenConfig
    ) internal override {
        uint256 _nativeValue;

        // Get the amount to send and then clear it.
        uint256 _amount = outbox[_token].balance;
        delete outbox[_token].balance;

        // Increment the nonce.
        uint64 _nonce = ++outbox[_token].nonce;

        if(_tokenConfig.remoteToken == address(0))
            revert TOKEN_NOT_CONFIGURED(_token);

        // if(_token != JBConstants.NATIVE_TOKEN){
        //     // Approve the tokens to be bridged.
        //     SafeERC20.forceApprove(IERC20(_token), address(OPMESSENGER), _amount);

        //     // Bridge the tokens to the payer address.
        //     OPMESSENGER.bridgeERC20To({
        //         localToken: _token,
        //         remoteToken: _tokenConfig.remoteToken,
        //         to: PEER,
        //         amount: _amount,
        //         minGasLimit: _tokenConfig.minGas,
        //         extraData: bytes('')
        //     });
        // } else {
        //     _nativeValue = _amount;
        // }

        // // Send the messenger to the peer with the redeemed ETH.
        // OPMESSENGER.sendMessage{value: _nativeValue}(
        //     PEER,
        //     abi.encodeCall(
        //         BPSucker.fromRemote,
        //         (
        //             MessageRoot({
        //                 token: _tokenConfig.remoteToken,
        //                 amount: _amount,
        //                 remoteRoot: RemoteRoot({
        //                     nonce: _nonce,
        //                     root: outbox[_token].tree.root()
        //                 })
        //             })
        //         )
        //     ),
        //     MESSENGER_BASE_GAS_LIMIT
        // );
    }

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer. 
    /// @param _sender the message sender.
    function _isRemotePeer(
        address _sender
    ) internal override returns (bool _valid) {
        // We are the L1 peer.
        if(LAYER == Layer.L1) {
            IBridge _bridge = INBOX.bridge();
            // Check that the sender is the bridge and that the outbox has our peer as the sender.
            return _sender == address(_bridge) &&
                address(PEER) == IOutbox(_bridge.activeOutbox()).l2ToL1Sender();
        }

        // We are the L2 peer.
        return _sender == AddressAliasHelper.applyL1ToL2Alias(address(PEER));
    }
}
