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

    /// @notice The gateways that require token approvals for bridging.
    address public immutable L1_ERC20_GATEWAY = 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;
    address public immutable L2_ERC20_GATEWAY = 0x09e9222E96E7B4AE2a407B98d48e330053351EEe;

    /// @notice The testnet gateways that require token approvals for bridging.
    address public immutable L1_SEP_ERC20_GATEWAY = 0x902b3E5f8F19571859F4AB1003B960a5dF693aFF;
    address public immutable L2_SEP_ERC20_GATEWAY = 0x6e244cD02BBB8a6dbd7F626f05B2ef82151Ab502;

    /// @notice To be set and used by the contract conditionally.
    bool public IS_TESTNET_SUCKER;

    /// @notice The chain id where this contract is deployed.
    uint256 public immutable CHAIN_ID;

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

        LAYER = layer;
        INBOX = IInbox(inbox);
        CHAIN_ID = block.chainid;
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256 chainId) {
        if (CHAIN_ID == 1) return 42161;
        if (CHAIN_ID == 42161) return 1;
        if (CHAIN_ID == 11155111) return 421614;
        if (CHAIN_ID == 421614) return 11155111;
    }

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the gateway router address for the current chain
    /// @return gateway for the current chain.
    function gatewayRouter() internal view returns (address gateway) {
        if (CHAIN_ID == 1) return L1_GATEWAY_ROUTER;
        if (CHAIN_ID == 42161) return L2_GATEWAY_ROUTER;
        if (CHAIN_ID == 11155111) return L1_SEP_GATEWAY_ROUTER;
        if (CHAIN_ID == 421614) return L2_SEP_GATEWAY_ROUTER;
    }

    /// @notice Returns the token gateway address for the current chain, used for token approvals
    /// @return _erc20Gateway for the current chain.
    function erc20Gateway() internal view returns (address _erc20Gateway) {
        if (CHAIN_ID == 1) return L1_ERC20_GATEWAY;
        if (CHAIN_ID == 42161) return L2_ERC20_GATEWAY;
        if (CHAIN_ID == 11155111) return L1_SEP_ERC20_GATEWAY;
        if (CHAIN_ID == 421614) return L2_SEP_ERC20_GATEWAY;
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
            // TODO: Approve the tokens to be bridged?
            // TODO: ERC20 Gateway contract on L2 for address
            SafeERC20.forceApprove(IERC20(token), address(erc20Gateway()), amount);

            L2GatewayRouter(address(gatewayRouter())).outboundTransfer(
                remoteToken.addr, address(PEER), amount, bytes("")
            );
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
            SafeERC20.forceApprove(IERC20(token), address(erc20Gateway()), amount);

            // Perform the ERC-20 bridge transfer.
            L1GatewayRouter(address(gatewayRouter())).outboundTransferCustomRefund({
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
