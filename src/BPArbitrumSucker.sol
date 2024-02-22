// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import "./BPSucker.sol";

interface L2GatewayRouter {
    function outboundTransfer(address _l1Token, address _to, uint256 _amount, bytes calldata _data)
        external
        payable
        returns (bytes memory);
}

interface L1GatewayRouter {
    function outboundTransferCustomRefund(
        address _token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory);
}

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

    address public immutable GATEWAY_ROUTER;

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

        // TODO: Check if gateway supports `outboundTransferCustomRefund` if LAYER is L1.
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice uses the OPMESSENGER to send the root and assets over the bridge to the peer.
    /// @param _token the token to bridge for.
    /// @param _tokenConfig the config for the token to send.
    function _sendRoot(address _token, BPRemoteToken memory _tokenConfig) internal override {
        // Get the amount to send and then clear it.
        uint256 _amount = outbox[_token].balance;
        delete outbox[_token].balance;

        // Increment the nonce.
        uint64 _nonce = ++outbox[_token].nonce;

        if (_tokenConfig.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(_token);
        }

        // Build the calldata that will be send to the peer.
        bytes memory _data = abi.encodeCall(
            BPSucker.fromRemote,
            (
                BPMessageRoot({
                    token: _tokenConfig.addr,
                    amount: _amount,
                    remoteRoot: BPInboxTreeRoot({nonce: _nonce, root: outbox[_token].tree.root()})
                })
            )
        );

        // Depending on which layer we are on, we send the call to the other layer.
        if (LAYER == Layer.L1) {
            _toL2(_token, _amount, _data, _tokenConfig);
        } else {
            _toL1(_token, _amount, _data, _tokenConfig);
        }
    }

    function _toL1(address _token, uint256 _amount, bytes memory _data, BPRemoteToken memory _tokenConfig) internal {
        uint256 _nativeValue;

        // Sending a message to L1 does not require any payment.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        if (_token != JBConstants.NATIVE_TOKEN) {
            // TODO: Approve the tokens to be bridged?
            // SafeERC20.forceApprove(IERC20(_token), address(OPMESSENGER), _amount);

            L2GatewayRouter(GATEWAY_ROUTER).outboundTransfer(_tokenConfig.addr, address(PEER), _amount, bytes(""));
        } else {
            _nativeValue = _amount;
        }

        // address `100` is the ArbSys precompile address.
        ArbSys(address(100)).sendTxToL1{value: _nativeValue}(address(PEER), _data);
    }

    function _toL2(address _token, uint256 _amount, bytes memory _data, BPRemoteToken memory _tokenConfig) internal {
        uint256 _nativeValue;

        if (_token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(_token), address(GATEWAY_ROUTER), _amount);
            // Perform the ERC20 bridge transfer.
            L1GatewayRouter(GATEWAY_ROUTER).outboundTransferCustomRefund({
                _token: _token,
                // TODO: Something about these 2 address with needing to be aliassed.
                _refundTo: address(PEER),
                _to: address(PEER),
                _amount: _amount,
                _maxGas: _tokenConfig.minGas,
                // TODO: Is this a sane default?
                _gasPriceBid: 1 gwei,
                _data: bytes((""))
            });
        } else {
            _nativeValue = _amount;
        }

        // Create the retryable ticket that contains the merkleRoot.
        // We could even make this unsafe.
        INBOX.createRetryableTicket{value: _nativeValue + msg.value}({
            to: address(PEER),
            l2CallValue: _nativeValue,
            // TODO: Check, We get the cost... is this right? this seems odd.
            maxSubmissionCost: INBOX.calculateRetryableSubmissionFee(_data.length, block.basefee),
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: PEER,
            gasLimit: MESSENGER_BASE_GAS_LIMIT,
            // TODO: Is this a sane default?
            maxFeePerGas: 1 gwei,
            data: _data
        });
    }

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer.
    /// @param _sender the message sender.
    function _isRemotePeer(address _sender) internal override returns (bool _valid) {
        // We are the L1 peer.
        if (LAYER == Layer.L1) {
            IBridge _bridge = INBOX.bridge();
            // Check that the sender is the bridge and that the outbox has our peer as the sender.
            return _sender == address(_bridge) && address(PEER) == IOutbox(_bridge.activeOutbox()).l2ToL1Sender();
        }

        // We are the L2 peer.
        return _sender == AddressAliasHelper.applyL1ToL2Alias(address(PEER));
    }
}
