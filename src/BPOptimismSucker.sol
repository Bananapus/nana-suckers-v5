// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./BPSucker.sol";
import "./BPSuckerHook.sol";

import {OPMessenger} from "./interfaces/OPMessenger.sol";
import {OPStandardBridge} from "./interfaces/OPStandardBridge.sol";

/// @notice A `BPSucker` implementation to suck tokens between two chains connected by an OP Bridge.
contract BPOptimismSucker is BPSucker, BPSuckerHook {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    event SuckingToRemote(address token, uint64 nonce);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The messenger used to send messages between the local and remote sucker.
    OPMessenger public immutable OPMESSENGER;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    OPStandardBridge public immutable OPBRIDGE;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBPrices prices,
        IJBRulesets rulesets,
        OPMessenger messenger,
        OPStandardBridge bridge,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        uint256 projectId
    ) BPSucker(directory, tokens, permissions, peer, projectId) BPSuckerHook(prices, rulesets) {
        OPMESSENGER = messenger;
        OPBRIDGE = bridge;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Use the `OPMESSENGER` to send the outbox tree for the `token` and the corresponding funds to the peer over the `OPBRIDGE`.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(address token, BPRemoteToken memory remoteToken) internal override {
        uint256 nativeValue;

        // Revert if there's a `msg.value`. The OP bridge does not expect to be paid.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteToken.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // If the token is an ERC20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens bing bridged.
            SafeERC20.forceApprove(IERC20(token), address(OPBRIDGE), amount);

            // Bridge the tokens to the peer sucker.
            OPBRIDGE.bridgeERC20To({
                localToken: token,
                remoteToken: remoteToken.addr,
                to: PEER,
                amount: amount,
                minGasLimit: remoteToken.minGas,
                extraData: bytes("")
            });
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        // Send the message to the peer with the redeemed ETH.
        OPMESSENGER.sendMessage{value: nativeValue}(
            PEER,
            abi.encodeCall(
                BPSucker.fromRemote,
                (
                    BPMessageRoot({
                        token: remoteToken.addr,
                        amount: amount,
                        remoteRoot: BPInboxTreeRoot({nonce: nonce, root: outbox[token].tree.root()})
                    })
                )
            ),
            MESSENGER_BASE_GAS_LIMIT
        );

        // Emit an event for the relayers to watch for.
        emit SuckingToRemote(token, nonce);
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal override returns (bool valid) {
        return sender == address(OPMESSENGER) && OPMESSENGER.xDomainMessageSender() == PEER;
    }
}
