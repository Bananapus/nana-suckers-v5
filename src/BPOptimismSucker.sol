// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {OPMessenger} from "./interfaces/OPMessenger.sol";

import "./BPSucker.sol";


interface OpStandardBridge {
    /**
     * @notice Sends ERC20 tokens to a receiver's address on the other chain. Note that if the
     *         ERC20 token on the other chain does not recognize the local token as the correct
     *         pair token, the ERC20 bridge will fail and the tokens will be returned to sender on
     *         this chain.
     *
     * @param localToken  Address of the ERC20 on this chain.
     * @param remoteToken Address of the corresponding token on the remote chain.
     * @param to          Address of the receiver.
     * @param amount      Amount of local tokens to deposit.
     * @param minGasLimit Minimum amount of gas that the bridge can be relayed with.
     * @param extraData   Extra data to be sent with the transaction. Note that the recipient will
     *                     not be triggered with this data, but it will be emitted and can be used
     *                     to identify the transaction.
     */
    function bridgeERC20To(
        address localToken,
        address remoteToken,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external;
}

/// @notice A contract that sucks tokens from one chain to another.
/// @dev This implementation is designed to be deployed on two chains that are connected by an OP bridge.
contract BPOptimismSucker is BPSucker {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The messenger in use to send messages between the local and remote sucker.
    OPMessenger public immutable OPMESSENGER;

    OpStandardBridge public immutable OPBRIDGE;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        OPMessenger _messenger,
        OpStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions,
        address _peer,
        uint256 _projectId
    ) BPSucker(_directory, _tokens, _permissions, _peer, _projectId) {
        OPMESSENGER = _messenger;
        OPBRIDGE = _bridge;
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

        // The OP bridge does not expect to be paid.
        if(msg.value != 0)
            revert UNEXPECTED_MSG_VALUE();

        // Get the amount to send and then clear it.
        uint256 _amount = outbox[_token].balance;
        delete outbox[_token].balance;

        // Increment the nonce.
        uint64 _nonce = ++outbox[_token].nonce;

        if(_tokenConfig.remoteToken == address(0))
            revert TOKEN_NOT_CONFIGURED(_token);

        if(_token != JBConstants.NATIVE_TOKEN){
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(_token), address(OPBRIDGE), _amount);

            // Bridge the tokens to the payer address.
            OPBRIDGE.bridgeERC20To({
                localToken: _token,
                remoteToken: _tokenConfig.remoteToken,
                to: PEER,
                amount: _amount,
                minGasLimit: _tokenConfig.minGas,
                extraData: bytes('')
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
                        remoteRoot: RemoteRoot({
                            nonce: _nonce,
                            root: outbox[_token].tree.root()
                        })
                    })
                )
            ),
            MESSENGER_BASE_GAS_LIMIT
        );
    }

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer. 
    /// @param _sender the message sender.
    function _isRemotePeer(
        address _sender
    ) internal override returns (bool _valid) {
        return _sender == address(OPMESSENGER) && OPMESSENGER.xDomainMessageSender() == PEER;
    }
}
