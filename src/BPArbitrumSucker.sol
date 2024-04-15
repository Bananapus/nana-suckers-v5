// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IBridge} from "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import {L1GatewayRouter} from "./interfaces/L1GatewayRouter.sol";
import {L2GatewayRouter} from "./interfaces/L2GatewayRouter.sol";
import {IGatewayRouter} from "./interfaces/IGatewayRouter.sol";
import {BPRemoteToken} from "./structs/BPRemoteToken.sol";
import {BPInboxTreeRoot} from "./structs/BPInboxTreeRoot.sol";
import {BPMessageRoot} from "./structs/BPMessageRoot.sol";
import {BPLayer} from "./enums/BPLayer.sol";
import {BPSucker, BPAddToBalanceMode} from "./BPSucker.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

/// @notice A `BPSucker` implementation to suck tokens between two chains connected by an Arbitrum bridge.
// NOTICE: UNFINISHED!
contract BPArbitrumSucker is BPSucker {
    error L1GatewayUnsupported();
    error ChainNotSupported();

    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The layer that this contract is on.
    BPLayer public immutable LAYER;

    /// @notice The gateway router used to bridge tokens between the local and remote chain.
    address public immutable L1_GATEWAY_ROUTER = 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    address public immutable L2_GATEWAY_ROUTER = 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;

    /// @notice The testnet gateway routers used for briding tokens.
    address public immutable L1_SEP_GATEWAY_ROUTER = 0xcE18836b233C83325Cc8848CA4487e94C6288264;
    address public immutable L2_SEP_GATEWAY_ROUTER = 0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7;

    /// @notice The chain id where this contract is deployed.
    uint256 public immutable CHAIN_ID;

    /// @notice Chains and their respective ids.
    uint256 public immutable ETH_CHAINID = 1;
    uint256 public immutable ETH_SEP_CHAINID = 11155111;
    uint256 public immutable ARB_CHAINID = 42161;
    uint256 public immutable ARB_SEP_CHAINID = 421614;

    /// @notice The inbox used to send messages between the local and remote sucker.
    IInbox public immutable INBOX;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        address inbox,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        uint256 projectId,
        BPAddToBalanceMode atbMode
    ) BPSucker(directory, tokens, permissions, peer, projectId, atbMode) {
        // Check if gateway supports `outboundTransferCustomRefund` if LAYER is L1.
        /// @note not sure if this is needed but leaving it commented for now.
        /* if (
            LAYER == BPLayer.L1
                && !IERC165(gatewayRouter).supportsInterface(L1GatewayRouter.outboundTransferCustomRefund.selector)
        ) {
            revert L1GatewayUnsupported();
        } */

        uint256 _chainId = block.chainid;
        INBOX = IInbox(inbox);
        CHAIN_ID = _chainId;

        // Set LAYER based on the chain ID.
        if (_chainId == ETH_CHAINID || _chainId == ETH_SEP_CHAINID) LAYER = BPLayer.L1;
        if (_chainId == ARB_CHAINID || _chainId == ARB_SEP_CHAINID) LAYER = BPLayer.L2;

        // If LAYER is left uninitialized, the chain is not currently supported.
        if (uint256(LAYER) == 0) revert ChainNotSupported();
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256 chainId) {
        if (CHAIN_ID == ETH_CHAINID) return ARB_CHAINID;
        if (CHAIN_ID == ARB_CHAINID) return ETH_CHAINID;
        if (CHAIN_ID == ETH_SEP_CHAINID) return ARB_SEP_CHAINID;
        if (CHAIN_ID == ARB_SEP_CHAINID) return ETH_SEP_CHAINID;
    }

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the gateway router address for the current chain
    /// @return gateway for the current chain.
    function gatewayRouter() internal view returns (IGatewayRouter gateway) {
        if (CHAIN_ID == ETH_CHAINID) return IGatewayRouter(L1_GATEWAY_ROUTER);
        if (CHAIN_ID == ARB_CHAINID) return IGatewayRouter(L2_GATEWAY_ROUTER);
        if (CHAIN_ID == ETH_SEP_CHAINID) return IGatewayRouter(L1_SEP_GATEWAY_ROUTER);
        if (CHAIN_ID == ARB_SEP_CHAINID) return IGatewayRouter(L2_SEP_GATEWAY_ROUTER);
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Uses the L1/L2 gateway to send the root and assets over the bridge to the peer.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, BPRemoteToken memory remoteToken) internal override {
        // TODO: Handle the `transportPayment`
        if (transportPayment == 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

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
            IGatewayRouter _router = gatewayRouter();

            SafeERC20.forceApprove(IERC20(token), _router.getGateway(token), amount);

            L2GatewayRouter(address(_router)).outboundTransfer(remoteToken.addr, address(PEER), amount, bytes(""));
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
            IGatewayRouter _router = gatewayRouter();

            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(token), _router.getGateway(token), amount);

            // Perform the ERC-20 bridge transfer.
            L1GatewayRouter(address(_router)).outboundTransferCustomRefund({
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
            // Question: is this the right refund address? If so do these suckers need recovery methods?
            callValueRefundAddress: PEER,
            gasLimit: MESSENGER_BASE_GAS_LIMIT,
            // TODO: Is this a sane default?
            maxFeePerGas: 1 gwei,
            data: data
        });
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
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
