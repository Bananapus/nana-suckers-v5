// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {JBAddToBalanceMode} from "./enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "./interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./interfaces/IJBSuckerDeployer.sol";
import {JBClaim} from "./structs/JBClaim.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBOutboxTree} from "./structs/JBOutboxTree.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBTokenMapping} from "./structs/JBTokenMapping.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

/// @notice An abstract contract for bridging a Juicebox project's tokens and the corresponding funds to and from a remote chain.
/// @dev Beneficiaries and balances are tracked on two merkle trees: the outbox tree is used to send from the local chain to the remote chain, and the inbox tree is used to receive from the remote chain to the local chain.
/// @dev Throughout this contract, "terminal token" refers to any token accepted by a project's terminal.
/// @dev This contract does *NOT* support tokens that have a fee on regular transfers and rebasing tokens.
abstract contract JBSucker is JBPermissioned, IJBSucker {
    using BitMaps for BitMaps.BitMap;
    using MerkleLib for MerkleLib.Tree;
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSucker_BelowMinGas();
    error JBSucker_BeneficiaryNotAllowed();
    error JBSucker_ERC20TokenRequired();
    error JBSucker_InsufficientBalance();
    error JBSucker_InvalidNativeRemoteAddress();
    error JBSucker_InvalidProof();
    error JBSucker_LeafAlreadyExecuted();
    error JBSucker_ManualNotAllowed();
    error JBSucker_NoTerminalForToken();
    error JBSucker_NotPeer();
    error JBSucker_QueueInsufficientSize();
    error JBSucker_TokenNotMapped();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice A reasonable minimum gas limit for a basic cross-chain call. The minimum amount of gas required to call the `fromRemote` (successfully/safely) on the remote chain.
    uint32 constant MESSENGER_BASE_GAS_LIMIT = 300_000;

    /// @notice A reasonable minimum gas limit used when bridging ERC-20s. The minimum amount of gas required to (successfully/safely) perform a transfer on the remote chain.
    uint32 constant MESSENGER_ERC20_MIN_GAS_LIMIT = 200_000;

    //*********************************************************************//
    // ------------------------- internal constants ----------------------- //
    //*********************************************************************//

    /// @notice The depth of the merkle tree used to store the outbox and inbox.
    uint32 constant _TREE_DEPTH = 32;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Whether the `amountToAddToBalance` gets added to the project's balance automatically when `claim` is called or manually by calling `addOutstandingAmountToBalance`.
    JBAddToBalanceMode public immutable ADD_TO_BALANCE_MODE;

    /// @notice The address of this contract's deployer.
    address public immutable DEPLOYER;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The peer sucker on the remote chain.
    address public immutable override PEER;

    /// @notice The ID of the project (on the local chain) that this sucker is associated with.
    uint256 public immutable PROJECT_ID;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The outstanding amount of tokens to be added to the project's balance by `claim` or `addOutstandingAmountToBalance`.
    mapping(address token => uint256 amount) public amountToAddToBalance;

    /// @notice The inbox merkle tree root for a given token.
    mapping(address token => JBInboxTreeRoot root) public inbox;

    /// @notice The outbox merkle tree for a given token.
    mapping(address token => JBOutboxTree) public outbox;

    /// @notice Information about the token on the remote chain that the given token on the local chain is mapped to.
    mapping(address token => JBRemoteToken remoteToken) public remoteTokenFor;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Tracks whether individual leaves in a given token's merkle tree have been executed (to prevent double-spending).
    /// @dev A leaf is "executed" when the tokens it represents are minted for its beneficiary.
    mapping(address token => BitMaps.BitMap) _executed;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param permissions A contract storing permissions.
    /// @param tokens A contract that manages token minting and burning.
    /// @param peer The address of the peer sucker on the remote chain.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    /// @param projectId The ID of the project (on the local chain) that this sucker is associated with.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address peer,
        JBAddToBalanceMode addToBalanceMode,
        uint256 projectId
    ) JBPermissioned(permissions) {
        DIRECTORY = directory;
        TOKENS = tokens;
        PEER = peer == address(0) ? address(this) : peer;
        DEPLOYER = msg.sender;
        ADD_TO_BALANCE_MODE = addToBalanceMode;
        PROJECT_ID = projectId;

        // Sanity check: make sure the merkle lib uses the same tree depth.
        assert(MerkleLib.TREE_DEPTH == _TREE_DEPTH);
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Checks whether the specified token is mapped to a remote token.
    /// @param token The terminal token to check.
    /// @return A boolean which is `true` if the token is mapped to a remote token and `false` if it is not.
    function isMapped(address token) external view override returns (bool) {
        return remoteTokenFor[token].addr != address(0);
    }

    /// @notice Returns the chain on which the peer is located.
    /// @return chain ID of the peer.
    function peerChainID() external view virtual returns (uint256);

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Helper to get the `addr`'s balance for a given `token`.
    /// @param token The token to get the balance for.
    /// @param addr The address to get the `token` balance of.
    /// @return balance The address' `token` balance.
    function _balanceOf(address token, address addr) internal view returns (uint256 balance) {
        if (token == JBConstants.NATIVE_TOKEN) {
            return addr.balance;
        }

        return IERC20(token).balanceOf(addr);
    }

    /// @notice Builds a hash as they are stored in the merkle tree.
    /// @param projectTokenCount The number of project tokens being redeemed.
    /// @param terminalTokenAmount The amount of terminal tokens being reclaimed by the redemption.
    /// @param beneficiary The beneficiary which will receive the project tokens.
    function _buildTreeHash(uint256 projectTokenCount, uint256 terminalTokenAmount, address beneficiary)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(projectTokenCount, terminalTokenAmount, beneficiary));
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Adds the redeemed `token` balance to the projects terminal. Can only be used if `ADD_TO_BALANCE_MODE` is `MANUAL`.
    /// @param token The address of the terminal token to add to the project's balance.
    function addOutstandingAmountToBalance(address token) external {
        if (ADD_TO_BALANCE_MODE != JBAddToBalanceMode.MANUAL) {
            revert JBSucker_ManualNotAllowed();
        }

        // Add entire outstanding amount to the project's balance.
        _addToBalance(token, amountToAddToBalance[token]);
    }

    /// @notice Performs multiple claims.
    /// @param claims A list of claims to perform (including the terminal token, merkle tree leaf, and proof for each claim).
    function claim(JBClaim[] calldata claims) external {
        // Get the number of claims to perform.
        uint256 numberOfClaims = claims.length;

        // Claim each.
        for (uint256 i; i < numberOfClaims; i++) {
            claim(claims[i]);
        }
    }

    /// @notice `JBClaim` project tokens which have been bridged from the remote chain for their beneficiary.
    /// @param claimData The terminal token, merkle tree leaf, and proof for the claim.
    function claim(JBClaim calldata claimData) public {
        // Attempt to validate the proof against the inbox tree for the terminal token.
        _validate({
            projectTokenCount: claimData.leaf.projectTokenCount,
            terminalToken: claimData.token,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            beneficiary: claimData.leaf.beneficiary,
            index: claimData.leaf.index,
            leaves: claimData.proof
        });

        emit Claimed({
            beneficiary: claimData.leaf.beneficiary,
            token: claimData.token,
            projectTokenCount: claimData.leaf.projectTokenCount,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            index: claimData.leaf.index,
            autoAddedToBalance: ADD_TO_BALANCE_MODE == JBAddToBalanceMode.ON_CLAIM ? true : false,
            caller: msg.sender
        });

        // If this contract's add to balance mode is `ON_CLAIM`, add the redeemed funds to the project's balance.
        if (ADD_TO_BALANCE_MODE == JBAddToBalanceMode.ON_CLAIM) {
            _addToBalance({token: claimData.token, amount: claimData.leaf.terminalTokenAmount});
        }

        // Mint the project tokens for the beneficiary.
        // slither-disable-next-line calls-loop,unused-return
        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).mintTokensOf({
            projectId: PROJECT_ID,
            tokenCount: claimData.leaf.projectTokenCount,
            beneficiary: claimData.leaf.beneficiary,
            memo: "",
            useReservedPercent: false
        });
    }

    /// @notice Receive a merkle root for a terminal token from the remote project.
    /// @dev This can only be called by the messenger contract on the local chain, with a message from the remote peer.
    /// @param root The merkle root, token, and amount being received.
    function fromRemote(JBMessageRoot calldata root) external payable {
        // Make sure that the message came from our peer.
        if (!_isRemotePeer(msg.sender)) {
            revert JBSucker_NotPeer();
        }

        // Increase the outstanding amount to be added to the project's balance by the amount being received.
        amountToAddToBalance[root.token] += root.amount;

        // If the received tree's nonce is greater than the current inbox tree's nonce, update the inbox tree.
        // We can't revert because this could be a native token transfer. If we reverted, we would lose the native tokens.
        if (root.remoteRoot.nonce > inbox[root.token].nonce) {
            inbox[root.token] = root.remoteRoot;
            emit NewInboxTreeRoot({
                token: root.token,
                nonce: root.remoteRoot.nonce,
                root: root.remoteRoot.root,
                caller: msg.sender
            });
        }
    }

    /// @notice Map an ERC-20 token on the local chain to an ERC-20 token on the remote chain, allowing that token to be bridged.
    /// @param map The local and remote terminal token addresses to map, and minimum amount/gas limits for bridging them.
    function mapToken(JBTokenMapping calldata map) public {
        address token = map.localToken;
        bool isNative = map.localToken == JBConstants.NATIVE_TOKEN;

        // If the token being mapped is the native token, the `remoteToken` must also be the native token.
        // The native token can also be mapped to the 0 address, which is used to disable native token bridging.
        if (isNative && map.remoteToken != JBConstants.NATIVE_TOKEN && map.remoteToken != address(0)) {
            revert JBSucker_InvalidNativeRemoteAddress();
        }

        // Enforce a reasonable minimum gas limit for bridging. A minimum which is too low could lead to the loss of funds.
        if (map.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && !isNative) {
            revert JBSucker_BelowMinGas();
        }

        // The caller must be the project owner or have the `QUEUE_RULESETS` permission from them.
        // slither-disable-next-line calls-loop
        _requirePermissionFrom({
            account: DIRECTORY.PROJECTS().ownerOf(PROJECT_ID),
            projectId: PROJECT_ID,
            permissionId: JBPermissionIds.MAP_SUCKER_TOKEN
        });

        // If the remote token is being set to the 0 address (which disables bridging), send any remaining outbox funds to the remote chain.
        if (map.remoteToken == address(0) && outbox[token].balance != 0) {
            _sendRoot({transportPayment: 0, token: token, remoteToken: remoteTokenFor[token]});
        }

        // Update the token mapping.
        remoteTokenFor[token] =
            JBRemoteToken({minGas: map.minGas, addr: map.remoteToken, minBridgeAmount: map.minBridgeAmount});
    }

    /// @notice Map multiple ERC-20 tokens on the local chain to ERC-20 tokens on the remote chain, allowing those tokens to be bridged.
    /// @param maps A list of local and remote terminal token addresses to map, and minimum amount/gas limits for bridging them.
    function mapTokens(JBTokenMapping[] calldata maps) external {
        // Keep a reference to the number of token mappings to perform.
        uint256 numberOfMaps = maps.length;

        // Perform each token mapping.
        for (uint256 i; i < numberOfMaps; i++) {
            mapToken(maps[i]);
        }
    }

    /// @notice Prepare project tokens and the redemption amount backing them to be bridged to the remote chain.
    /// @dev This adds the tokens and funds to the outbox tree for the `token`. They will be bridged by the next call to `toRemote` for the same `token`.
    /// @param projectTokenCount The number of project tokens to prepare for bridging.
    /// @param beneficiary The address of the recipient of the tokens on the remote chain.
    /// @param minTokensReclaimed The minimum amount of terminal tokens to redeem for. If the amount reclaimed is less than this, the transaction will revert.
    /// @param token The address of the terminal token to redeem for.
    function prepare(uint256 projectTokenCount, address beneficiary, uint256 minTokensReclaimed, address token)
        external
    {
        // Make sure the beneficiary is not the zero address, as this would revert when minting on the remote chain.
        if (beneficiary == address(0)) {
            revert JBSucker_BeneficiaryNotAllowed();
        }

        // Get the project's token.
        IERC20 projectToken = IERC20(address(TOKENS.tokenOf(PROJECT_ID)));
        if (address(projectToken) == address(0)) {
            revert JBSucker_ERC20TokenRequired();
        }

        // Make sure that the token is mapped to a remote token.
        if (remoteTokenFor[token].addr == address(0)) {
            revert JBSucker_TokenNotMapped();
        }

        // Transfer the tokens to this contract.
        // slither-disable-next-line reentrancy-events,reentrancy-benign
        projectToken.safeTransferFrom({from: msg.sender, to: address(this), value: projectTokenCount});

        // Redeem the tokens.
        // slither-disable-next-line reentrancy-events,reentrancy-benign
        uint256 terminalTokenAmount = _pullBackingAssets({
            projectToken: projectToken,
            count: projectTokenCount,
            token: token,
            minTokensReclaimed: minTokensReclaimed
        });

        // Insert the item into the outbox tree for the terminal `token`.
        _insertIntoTree({
            projectTokenCount: projectTokenCount,
            token: token,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary
        });
    }

    /// @notice Redeems project tokens for terminal tokens.
    /// @param projectToken The project token being redeemed.
    /// @param count The number of project tokens to redeem.
    /// @param token The terminal token to redeem for.
    /// @param minTokensReclaimed The minimum amount of terminal tokens to reclaim. If the amount reclaimed is less than this, the transaction will revert.
    /// @return reclaimedAmount The amount of terminal tokens reclaimed by the redemption.
    function _pullBackingAssets(IERC20 projectToken, uint256 count, address token, uint256 minTokensReclaimed)
        internal
        virtual
        returns (uint256 reclaimedAmount)
    {
        projectToken;

        // Get the project's primary terminal for `token`. We will redeem from this terminal.
        IJBRedeemTerminal terminal =
            IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf({projectId: PROJECT_ID, token: token})));

        // If the project doesn't have a primary terminal for `token`, revert.
        if (address(terminal) == address(0)) {
            revert JBSucker_NoTerminalForToken();
        }

        // Redeem the tokens.
        uint256 balanceBefore = _balanceOf(token, address(this));
        reclaimedAmount = terminal.redeemTokensOf({
            holder: address(this),
            projectId: PROJECT_ID,
            tokenToReclaim: token,
            redeemCount: count,
            minTokensReclaimed: minTokensReclaimed,
            beneficiary: payable(address(this)),
            metadata: bytes("")
        });

        // Sanity check to make sure we received the expected amount.
        // This prevents malicious terminals from reporting amounts other than what they send.
        // slither-disable-next-line incorrect-equality
        assert(reclaimedAmount == _balanceOf(token, address(this)) - balanceBefore);
    }

    /// @notice Bridge the project tokens, redeemed funds, and beneficiary information for a given `token` to the remote chain.
    /// @dev This sends the outbox root for the specified `token` to the remote chain.
    /// @param token The terminal token being bridged.
    function toRemote(address token) external payable {
        JBRemoteToken memory remoteToken = remoteTokenFor[token];

        // Ensure that the amount being bridged exceeds the minimum bridge amount.
        if (outbox[token].balance < remoteToken.minBridgeAmount) {
            revert JBSucker_QueueInsufficientSize();
        }

        // Send the merkle root to the remote chain.
        _sendRoot({transportPayment: msg.value, token: token, remoteToken: remoteToken});
    }

    //*********************************************************************//
    // ---------------------------- receive  ----------------------------- //
    //*********************************************************************//

    /// @notice Used to receive redeemed native tokens.
    receive() external payable {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Adds funds to the projects balance.
    /// @param token The terminal token to add to the project's balance.
    /// @param amount The amount of terminal tokens to add to the project's balance.
    function _addToBalance(address token, uint256 amount) internal {
        // Make sure that the current `amountToAddToBalance` is greater than or equal to the amount being added.
        uint256 addableAmount = amountToAddToBalance[token];
        if (amount > addableAmount) {
            revert JBSucker_InsufficientBalance();
        }

        // Update the outstanding amount of tokens which can be added to the project's balance.
        unchecked {
            amountToAddToBalance[token] = addableAmount - amount;
        }

        // Get the project's primary terminal for the token.
        // slither
        // slither-disable-next-line calls-loop
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf({projectId: PROJECT_ID, token: token});
        // slither-disable-next-line incorrect-equality
        if (address(terminal) == address(0)) revert JBSucker_NoTerminalForToken();

        // Perform the `addToBalance`.
        if (token != JBConstants.NATIVE_TOKEN) {
            // slither-disable-next-line calls-loop
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});

            // slither-disable-next-line calls-loop
            terminal.addToBalanceOf({
                projectId: PROJECT_ID,
                token: token,
                amount: amount,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: ""
            });

            // Sanity check: make sure we transfer the full amount.
            // slither-disable-next-line calls-loop,incorrect-equality
            assert(IERC20(token).balanceOf(address(this)) == balanceBefore - amount);
        } else {
            // If the token is the native token, use `msg.value`.
            // slither-disable-next-line arbitrary-send-eth,calls-loop
            terminal.addToBalanceOf({
                projectId: PROJECT_ID,
                token: token,
                amount: amount,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: ""
            });
        }
    }
    /// @notice Inserts a new leaf into the outbox merkle tree for the specified `token`.
    /// @param projectTokenCount The amount of project tokens being redeemed.
    /// @param token The terminal token being redeemed for.
    /// @param terminalTokenAmount The amount of terminal tokens reclaimed by redeeming.
    /// @param beneficiary The beneficiary of the project tokens on the remote chain.

    function _insertIntoTree(uint256 projectTokenCount, address token, uint256 terminalTokenAmount, address beneficiary)
        internal
    {
        // Build a hash based on the token amounts and the beneficiary.
        bytes32 hashed = _buildTreeHash({
            projectTokenCount: projectTokenCount,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary
        });

        // Create a new tree based on the outbox tree for the terminal token with the hash inserted.
        MerkleLib.Tree memory tree = outbox[token].tree.insert(hashed);

        // Update the outbox tree and balance for the terminal token.
        outbox[token].tree = tree;
        outbox[token].balance += terminalTokenAmount;

        emit InsertToOutboxTree({
            beneficiary: beneficiary,
            token: token,
            hashed: hashed,
            index: tree.count - 1, // Subtract 1 since we want the 0-based index.
            root: outbox[token].tree.root(),
            projectTokenCount: projectTokenCount,
            terminalTokenAmount: terminalTokenAmount,
            caller: msg.sender
        });
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal virtual returns (bool valid);

    /// @notice Send the outbox root for the specified token to the remote peer.
    /// @dev The call may have a `transportPayment` for bridging native tokens. Require it to be `0` if it is not needed. Make sure if a value being paid to the bridge is expected to revert if the given value is `0`.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message. (usually derived from `msg.value`)
    /// @param token The terminal token to bridge the merkle tree of.
    /// @param remoteToken The remote token which the `token` is mapped to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal virtual;

    /// @notice Validates a leaf as being in the inbox merkle tree and registers the leaf as executed (to prevent double-spending).
    /// @dev Reverts if the leaf is invalid.
    /// @param projectTokenCount The number of project tokens which were redeemed.
    /// @param terminalToken The terminal token that the project tokens were redeemed for.
    /// @param terminalTokenAmount The amount of terminal tokens reclaimed by the redemption.
    /// @param beneficiary The beneficiary which will receive the project tokens.
    /// @param index The index of the leaf being proved in the terminal token's inbox tree.
    /// @param leaves The leaves that prove that the leaf at the `index` is in the tree (i.e. the merkle branch that the leaf is on).
    function _validate(
        uint256 projectTokenCount,
        address terminalToken,
        uint256 terminalTokenAmount,
        address beneficiary,
        uint256 index,
        bytes32[_TREE_DEPTH] calldata leaves
    ) internal {
        // Make sure the leaf has not already been executed.
        if (_executed[terminalToken].get(index)) {
            revert JBSucker_LeafAlreadyExecuted();
        }

        // Register the leaf as executed to prevent double-spending.
        _executed[terminalToken].set(index);

        // Calculate the root based on the leaf, the branch, and the index.
        bytes32 root = MerkleLib.branchRoot({
            item: _buildTreeHash(projectTokenCount, terminalTokenAmount, beneficiary),
            branch: leaves,
            index: index
        });

        // Compare the calculated root to the terminal token's inbox root. Revert if they do not match.
        if (root != inbox[terminalToken].root) {
            revert JBSucker_InvalidProof();
        }
    }
}
