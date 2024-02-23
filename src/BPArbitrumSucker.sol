// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import {L1GatewayRouter} from "./interfaces/L1GatewayRouter.sol";
import {L2GatewayRouter} from "./interfaces/L2GatewayRouter.sol";

import {BPLayer} from "./enums/BPLayer.sol";

import "./BPSucker.sol";

/// @notice A `BPSucker` implementation to suck tokens between two chains connected by an Arbitrum bridge.
contract BPArbitrumSucker is BPSucker {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The layer that this contract is on.
    BPLayer public immutable LAYER;

    /// @notice The gateway router used to bridge tokens between the local and remote chain.
    address public immutable GATEWAY_ROUTER;

    /// @notice The inbox used to send messages between the local and remote sucker.
    IInbox public immutable INBOX;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        BPLayer layer,
        address inbox,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        uint256 projectId
    ) BPSucker(directory, tokens, permissions, peer, projectId) {
        LAYER = layer;
        INBOX = IInbox(inbox);

        // TODO: Check if gateway supports `outboundTransferCustomRefund` if LAYER is L1.
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Uses the L1/L2 gateway to send the root and assets over the bridge to the peer.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(address token, BPRemoteToken memory remoteToken) internal override {
        // Get the amount to send and then clear it.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        if (remoteToken.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Build the calldata that will be send to the peer. This will call `BPSucker.fromRemote` on the remote peer.
        bytes memory data = abi.encodeCall(
            BPSucker.fromRemote,
            (
                BPMessageRoot({
                    token: remoteToken.addr,
                    amount: amount,
                    remoteRoot: BPInboxTreeRoot({nonce: nonce, root: outbox[token].tree.root()})
                })
            )
        );

        // Depending on which layer we are on, send the call to the other layer.
        if (LAYER == BPLayer.L1) {
            _toL2(token, amount, data, remoteToken);
        } else {
            _toL1(token, amount, data, remoteToken);
        }
    }

    /// @notice Bridge the `token` and data to the remote L1 chain.
    /// @param token The token to bridge.
    /// @param amount The amount of tokens to bridge.
    /// @param data The calldata to send to the remote chain. This calls `BPSucker.fromRemote` on the remote peer.
    /// @param remoteToken Information about the remote token to bridged to.
    function _toL1(address token, uint256 amount, bytes memory data, BPRemoteToken memory remoteToken) internal {
        uint256 nativeValue;

        // Revert if there's a `msg.value`. Sending a message to L1 does not require any payment.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        // If the token is an ERC-20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // TODO: Approve the tokens to be bridged?
            // SafeERC20.forceApprove(IERC20(token), address(OPMESSENGER), amount);

            L2GatewayRouter(GATEWAY_ROUTER).outboundTransfer(remoteToken.addr, address(PEER), amount, bytes(""));
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        // Send the message to the peer with the redeemed ETH.
        // Address `100` is the ArbSys precompile address.
        ArbSys(address(100)).sendTxToL1{value: nativeValue}(address(PEER), data);
    }

    /// @notice Bridge the `token` and data to the remote L2 chain.
    /// @param token The token to bridge.
    /// @param amount The amount of tokens to bridge.
    /// @param data The calldata to send to the remote chain. This calls `BPSucker.fromRemote` on the remote peer.
    /// @param remoteToken Information about the remote token to bridged to.
    function _toL2(address token, uint256 amount, bytes memory data, BPRemoteToken memory remoteToken) internal {
        uint256 nativeValue;

        // If the token is an ERC-20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(token), address(GATEWAY_ROUTER), amount);

            // Perform the ERC-20 bridge transfer.
            L1GatewayRouter(GATEWAY_ROUTER).outboundTransferCustomRefund({
                _token: token,
                // TODO: Something about these 2 address with needing to be aliased.
                _refundTo: address(PEER),
                _to: address(PEER),
                _amount: amount,
                _maxGas: remoteToken.minGas,
                // TODO: Is this a sane default?
                _gasPriceBid: 1 gwei,
                _data: bytes((""))
            });
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        // Create the retryable ticket containing the merkleRoot.
        // TODO: We could even make this unsafe.
        INBOX.createRetryableTicket{value: nativeValue + msg.value}({
            to: address(PEER),
            l2CallValue: nativeValue,
            // TODO: Check, We get the cost... is this right? this seems odd.
            maxSubmissionCost: INBOX.calculateRetryableSubmissionFee(data.length, block.basefee),
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: PEER,
            gasLimit: MESSENGER_BASE_GAS_LIMIT,
            // TODO: Is this a sane default?
            maxFeePerGas: 1 gwei,
            data: data
        });
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal override returns (bool _valid) {
        // If we are the L1 peer,
        if (LAYER == BPLayer.L1) {
            IBridge bridge = INBOX.bridge();
            // Check that the sender is the bridge and that the outbox has our peer as the sender.
            return sender == address(bridge) && address(PEER) == IOutbox(bridge.activeOutbox()).l2ToL1Sender();
        }

        // If we are the L2 peer, check using the `AddressAliasHelper`.
        return sender == AddressAliasHelper.applyL1ToL2Alias(address(PEER));
    }
}
