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
    /// @param token the token to bridge for.
    /// @param tokenConfig the config for the token to send.
    function _sendRoot(address token, BPRemoteToken memory tokenConfig) internal override {
        // Get the amount to send and then clear it.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the nonce.
        uint64 nonce = ++outbox[token].nonce;

        if (tokenConfig.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Build the calldata that will be send to the peer.
        bytes memory data = abi.encodeCall(
            BPSucker.fromRemote,
            (
                BPMessageRoot({
                    token: tokenConfig.addr,
                    amount: amount,
                    remoteRoot: BPInboxTreeRoot({nonce: nonce, root: outbox[token].tree.root()})
                })
            )
        );

        // Depending on which layer we are on, we send the call to the other layer.
        if (LAYER == Layer.L1) {
            _toL2(token, amount, data, tokenConfig);
        } else {
            _toL1(token, amount, data, tokenConfig);
        }
    }

    function _toL1(address token, uint256 amount, bytes memory data, BPRemoteToken memory tokenConfig) internal {
        uint256 nativeValue;

        // Sending a message to L1 does not require any payment.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        if (token != JBConstants.NATIVE_TOKEN) {
            // TODO: Approve the tokens to be bridged?
            // SafeERC20.forceApprove(IERC20(token), address(OPMESSENGER), amount);

            L2GatewayRouter(GATEWAY_ROUTER).outboundTransfer(tokenConfig.addr, address(PEER), amount, bytes(""));
        } else {
            nativeValue = amount;
        }

        // address `100` is the ArbSys precompile address.
        ArbSys(address(100)).sendTxToL1{value: nativeValue}(address(PEER), data);
    }

    function _toL2(address token, uint256 amount, bytes memory data, BPRemoteToken memory tokenConfig) internal {
        uint256 nativeValue;

        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(token), address(GATEWAY_ROUTER), amount);
            // Perform the ERC20 bridge transfer.
            L1GatewayRouter(GATEWAY_ROUTER).outboundTransferCustomRefund({
                _token: token,
                // TODO: Something about these 2 address with needing to be aliassed.
                _refundTo: address(PEER),
                _to: address(PEER),
                _amount: amount,
                _maxGas: tokenConfig.minGas,
                // TODO: Is this a sane default?
                _gasPriceBid: 1 gwei,
                _data: bytes((""))
            });
        } else {
            nativeValue = amount;
        }

        // Create the retryable ticket that contains the merkleRoot.
        // We could even make this unsafe.
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

    /// @notice checks if the sender (msg.sender) is a valid representative of the remote peer.
    /// @param sender the message sender.
    function _isRemotePeer(address sender) internal override returns (bool _valid) {
        // We are the L1 peer.
        if (LAYER == Layer.L1) {
            IBridge bridge = INBOX.bridge();
            // Check that the sender is the bridge and that the outbox has our peer as the sender.
            return sender == address(bridge) && address(PEER) == IOutbox(bridge.activeOutbox()).l2ToL1Sender();
        }

        // We are the L2 peer.
        return sender == AddressAliasHelper.applyL1ToL2Alias(address(PEER));
    }
}
