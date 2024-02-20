// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IBPSucker} from "./interfaces/IBPSucker.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/terminal/IJBTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPayoutTerminal.sol";
import {IBPSuckerDeployerFeeless} from "./interfaces/IBPSuckerDeployerFeeless.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {BPTokenMapConfig} from "./structs/BPTokenMapConfig.sol";
import {BPRemoteTokenConfig} from "./structs/BPRemoteTokenConfig.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissioned, IJBPermissions} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBPermissionIds} from "@bananapus/core/src/libraries/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

/// @notice An abstract contract for bridging a Juicebox project's tokens and the corresponding funds to and from a remote chain.
/// @dev Beneficiaries and balances are tracked on two merkle trees: the outbox tree is used to send from the local chain to the remote chain, and the inbox tree is used to receive from the remote chain to the local chain.
abstract contract BPSucker is JBPermissioned, IBPSucker {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    /// @notice The depth of the merkle tree used to track beneficiaries, token balances, and redemption values.
    uint256 internal constant TREE_DEPTH = 32;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error NOT_PEER();
    error BELOW_MIN_GAS(uint256 minGas, uint256 suppliedGas);
    error ERC20_TOKEN_REQUIRED();
    error BENEFICIARY_NOT_ALLOWED();
    error NO_TERMINAL_FOR(uint256 projectId, address token);
    error INVALID_PROOF(bytes32 expectedRoot, bytes32 proofRoot);
    error LEAF_ALREADY_EXECUTED(uint256 index);
    error INSUFFICIENT_BALANCE();
    error TOKEN_NOT_MAPPED(address token);
    error MANUAL_NOT_ALLOWED();
    error UNEXPECTED_MSG_VALUE();

    event NewInboxTreeRoot(address indexed token, uint64 nonce, bytes32 root);

    event InsertToOutboxTree(
        address indexed beneficiary,
        address indexed redemptionToken,
        bytes32 hashed,
        uint256 index,
        bytes32 root,
        uint256 projectTokenAmount,
        uint256 redemptionTokenAmount
    );

    /// @notice A merkle tree used to track the outbox for a given token.
    /// @dev The outbox is used to send from the local chain to the remote chain.
    struct OutboxTree {
        uint64 nonce;
        uint256 balance;
        MerkleLib.Tree tree;
    }

    /// @notice The root of an inbox tree for a given token.
    /// @dev Inbox trees are used to receive from the remote chain to the local chain.
    /// @custom:member nonce Tracks the nonce of the tree. The nonce cannot decrease.
    /// @custom:member root The root of the tree.
    struct InboxTreeRoot {
        uint64 nonce;
        bytes32 root;
    }

    /// @notice Information about the remote (inbox) tree's root, passed in a message from the remote chain.
    /// @custom:member The address of the token that the tree tracks.
    /// @custom:member The amount of tokens being sent.
    /// @custom:member The root of the tree.
    struct MessageRoot {
        address token;
        uint256 amount;
        InboxTreeRoot remoteRoot;
    }

    /// @notice A leaf in the inbox or outbox tree. Used to `claim` tokens from the inbox tree.
    struct Leaf {
        uint256 index;
        address beneficiary;
        uint256 projectTokenAmount;
        uint256 redemptionTokenAmount;
    }

    struct Claim {
        address token;
        Leaf leaf;
        bytes32[TREE_DEPTH] proof;
    }

    /// @notice Options for how the `amountToAddToBalance` gets added to the project's balance.
    /// @custom:element MANUAL The amount gets added to the project's balance manually by calling `addOutstandingAmountToBalance`.
    /// @custom:element ON_CLAIM The amount gets added to the project's balance automatically when `claim` is called.
    enum AddToBalanceMode {
        MANUAL,
        ON_CLAIM
    }

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The outbox merkle tree for a given token.
    mapping(address token => OutboxTree) public outbox;

    /// @notice The inbox trees.
    mapping(address token => InboxTreeRoot root) public inbox;

    /// @notice The outstanding amount of tokens to be added to the project's balance by `claim` or `addOutstandingAmountToBalance`.
    mapping(address token => uint256 amount) public amountToAddToBalance;

    /// @notice The remote config for a given token.
    mapping(address token => BPRemoteTokenConfig remoteToken) public remoteConfigOf;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Whether the `amountToAddToBalance` gets added to the project's balance automatically when `claim` is called or manually by calling `addOutstandingAmountToBalance`.
    AddToBalanceMode public immutable ADD_TO_BALANCE_MODE;

    /// @notice The Juicebox Directory
    IJBDirectory public immutable DIRECTORY;

    /// @notice The Juicebox Tokenstore
    IJBTokens public immutable TOKENS;

    /// @notice The addres of the deployer.
    address public immutable DEPLOYER;

    /// @notice The peer sucker on the remote chain.
    address public immutable PEER;

    /// @notice the project ID this sucker is for (on this chain).
    uint256 public immutable PROJECT_ID;

    /// @notice The amount of gas the basic xchain call will use.
    uint32 constant MESSENGER_BASE_GAS_LIMIT = 300_000;

    /// @notice The minimum amount of gas an ERC20 bridge can be configured to.
    uint32 constant MESSENGER_ERC20_MIN_GAS_LIMIT = 200_000;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//
    /// @notice Tracks if a item has been executed or not, prevents double executing the same item.
    mapping(address _token => BitMaps.BitMap) executed;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        uint256 projectId
    ) JBPermissioned(permissions) {
        DIRECTORY = directory;
        TOKENS = tokens;
        PEER = peer == address(0) ? address(this) : peer;
        PROJECT_ID = projectId;

        // Sanity check: make sure the merkle lib uses the same tree depth.
        assert(MerkleLib.TREE_DEPTH == TREE_DEPTH);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Prepare project tokens and the redemption amount backing them to be bridged to the remote chain.
    /// @dev This adds the tokens and funds to the outbox tree, preparing them to be bridged by the next call to `toRemote`.
    /// @param projectTokenAmount the amount of tokens to move.
    /// @param beneficiary the recipient of the tokens on the remote chain.
    /// @param minRedeemedTokens the minimum amount of assets that gets moved.
    /// @param token the token to redeem for.
    function prepare(uint256 projectTokenAmount, address beneficiary, uint256 minRedeemedTokens, address token)
        external
    {
        // Make sure the beneficiary is not the zero address, as this would revert when minting on the remote chain.
        if (beneficiary == address(0)) {
            revert BENEFICIARY_NOT_ALLOWED();
        }

        // Get the token for the project.
        IERC20 projectToken = IERC20(address(TOKENS.tokenOf(PROJECT_ID)));
        if (address(projectToken) == address(0)) {
            revert ERC20_TOKEN_REQUIRED();
        }

        // Make sure that the token is configured to be sucked.
        if (remoteConfigOf[token].remoteToken == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Transfer the tokens to this contract.
        projectToken.transferFrom(msg.sender, address(this), projectTokenAmount);

        // Perform the redemption.
        uint256 redemptionTokenAmount =
            _getBackingAssets(projectToken, projectTokenAmount, token, minRedeemedTokens);

        // Insert the item.
        _insertIntoTree(projectTokenAmount, token, redemptionTokenAmount, beneficiary);
    }

    /// @notice Bridge funds for one or multiple beneficiaries.
    /// @param token the token to bridge the tree for.
    function toRemote(address token) external payable {
        // TODO: Add some way to prevent spam.
        BPRemoteTokenConfig memory tokenConfig = remoteConfigOf[token];

        // Require that the min amount being bridged is enough.
        if (outbox[token].balance < tokenConfig.minBridgeAmount) {
            revert();
        }

        // Send the root to the remote.
        _sendRoot(token, tokenConfig);
    }

    /// @notice Receive from the remote project.
    /// @dev can only be called by the OP messenger and with messages from the PEER.
    /// @param root the root and all the information regarding it.
    function fromRemote(MessageRoot calldata root) external payable {
        // Make sure that the message came from our peer.
        if (!_isRemotePeer(msg.sender)) {
            revert NOT_PEER();
        }

        // Increment the outstanding ATB amount with the amount being bridged.
        amountToAddToBalance[root.token] += root.amount;

        // If the nonce is a newer one than we already have we update it.
        // We can't revert in the case that this is a native token transfer
        // otherwise we would lose the native tokens.
        if (root.remoteRoot.nonce > inbox[root.token].nonce) {
            inbox[root.token] = root.remoteRoot;
            emit NewInboxTreeRoot(root.token, root.remoteRoot.nonce, root.remoteRoot.root);
        }
    }

    /// @notice Performs a claim.
    /// @param claimData The data for the claim.
    function claim(Claim calldata claimData) public {
        // Attempt to validate proof.
        _validate({
            projectTokenAmount: claimData.leaf.projectTokenAmount,
            redemptionToken: claimData.token,
            redemptionTokenAmount: claimData.leaf.redemptionTokenAmount,
            beneficiary: claimData.leaf.beneficiary,
            index: claimData.leaf.index,
            leaves: claimData.proof
        });

        // Perform the add to balance if this sucker is configured to perform it on claimData.
        if (ADD_TO_BALANCE_MODE == AddToBalanceMode.ON_CLAIM) {
            _addToBalance(claimData.token, claimData.leaf.redemptionTokenAmount);
        }

        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).mintTokensOf(
            PROJECT_ID, claimData.leaf.projectTokenAmount, claimData.leaf.beneficiary, "", false
        );
    }

    /// @notice Performs multiple claims.
    /// @param claims The data for the claims.
    function claim(Claim[] calldata claims) external {
        for (uint256 _i = 0; _i < claims.length; _i++) {
            claim(claims[_i]);
        }
    }

    /// @notice Adds the redeemed funds to the projects terminal. Can only be used if `AddToBalanceMode` is `MANUAL`.
    /// @param token The address of the token to add to the project's balance.
    function addOutstandingAmountToBalance(address token) external {
        if (ADD_TO_BALANCE_MODE != AddToBalanceMode.MANUAL) {
            revert MANUAL_NOT_ALLOWED();
        }

        // Add entire outstanding amount to the projects balance.
        _addToBalance(token, amountToAddToBalance[token]);
    }

    /// @notice Associate an ERC-20 token on the local chain with an ERC-20 token on the remote chain.
    /// @param config the configuration details.
    function mapToken(BPTokenMapConfig calldata config) public payable {
        address token = config.localToken;
        bool isNative = config.localToken == JBConstants.NATIVE_TOKEN;

        // If the native token is being configured then the remoteToken has to also be the native token.
        // Unless we are disabling native token bridging, then it can also be 0.
        if (isNative && config.remoteToken != JBConstants.NATIVE_TOKEN && config.remoteToken != address(0)) {
            revert();
        }

        // As misconfiguration can lead to loss of funds we enforce a reasonable minimum.
        if (config.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && !isNative) {
            revert BELOW_MIN_GAS(MESSENGER_ERC20_MIN_GAS_LIMIT, config.minGas);
        }

        // Access control.
        _requirePermissionFrom(DIRECTORY.PROJECTS().ownerOf(PROJECT_ID), PROJECT_ID, JBPermissionIds.QUEUE_RULESETS);

        // If we have a remaining balance in the outbox.
        // We send a final bridge before disabling so all users can exit with their funds.
        if (config.remoteToken == address(0) && outbox[token].balance != 0) _sendRoot(token, remoteConfigOf[token]);

        remoteConfigOf[token] = BPRemoteTokenConfig({
            minGas: config.minGas,
            remoteToken: config.remoteToken,
            minBridgeAmount: config.minBridgeAmount
        });
    }

    function mapTokens(BPTokenMapConfig[] calldata config) external payable {
        for (uint256 i = 0; i < config.length; i++) {
            mapToken(config[i]);
        }
    }

    /// @notice used to receive the redemption ETH.
    receive() external payable {}

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Checks whether the specified token is supported by this sucker.
    /// @param tokenAddr The token to check.
    /// @return A boolean which is `true` if the token is supported and `false` if it is not.
    function isSupported(address tokenAddr) external view override returns (bool) {
        return remoteConfigOf[tokenAddr].remoteToken != address(0);
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice inserts a new redemption into the sparse-merkle-tree
    /// @param projectTokenAmount the amount of project tokens redeemed.
    /// @param redemptionToken the token that the project tokens were redeemed for.
    /// @param redemptionTokenAmount the amount of redemptionTokens received.
    /// @param beneficiary the beneficiary of the tokens.
    function _insertIntoTree(
        uint256 projectTokenAmount,
        address redemptionToken,
        uint256 redemptionTokenAmount,
        address beneficiary
    ) internal {
        bytes32 hash = _buildTreeHash(projectTokenAmount, redemptionTokenAmount, beneficiary);

        // Insert the item into the tree.
        MerkleLib.Tree memory tree = outbox[redemptionToken].tree.insert(hash);

        // Update the outbox.
        outbox[redemptionToken].tree = tree;
        outbox[redemptionToken].balance += redemptionTokenAmount;

        emit InsertToOutboxTree(
            beneficiary,
            redemptionToken,
            hash,
            tree.count - 1, // -1 since we want the index.
            outbox[redemptionToken].tree.root(),
            projectTokenAmount,
            redemptionTokenAmount
        );
    }

    /// @notice Send the root to the remote peer.
    /// @dev Call may have a `msg.value`, require it to be `0` if its not needed.
    /// @param token the token to bridge for.
    /// @param tokenConfig the config for the token to send.
    function _sendRoot(address token, BPRemoteTokenConfig memory tokenConfig) internal virtual;

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer.
    /// @param sender the message sender.
    function _isRemotePeer(address sender) internal virtual returns (bool valid);

    /// @notice validates a leaf as being in the smt and registers as being redeemed.
    /// @dev Reverts if invalid.
    /// @param projectTokenAmount the amount of project tokens redeemed.
    /// @param redemptionToken the token that the project tokens were redeemed for.
    /// @param redemptionTokenAmount the amount of redemptionTokens received.
    /// @param beneficiary the beneficiary of the tokens.
    /// @param index the index of the leaf in the tree.
    /// @param leaves the leaves that proof the existence in the tree.
    function _validate(
        uint256 projectTokenAmount,
        address redemptionToken,
        uint256 redemptionTokenAmount,
        address beneficiary,
        uint256 index,
        bytes32[TREE_DEPTH] calldata leaves
    ) internal {
        // Make sure the item has not been executed before.
        if (executed[redemptionToken].get(index)) {
            revert LEAF_ALREADY_EXECUTED(index);
        }

        // Toggle it as being executed now.
        executed[redemptionToken].set(index);

        // Calculate the root from the proof.
        bytes32 root = MerkleLib.branchRoot({
            _item: _buildTreeHash(projectTokenAmount, redemptionTokenAmount, beneficiary),
            _branch: leaves,
            _index: index
        });

        // Compare the root.
        if (root != inbox[redemptionToken].root) {
            revert INVALID_PROOF(inbox[redemptionToken].root, root);
        }
    }

    /// @notice Adds funds to the projects balance.
    /// @param token the token to add.
    /// @param amount the amount of the token to add.
    function _addToBalance(address token, uint256 amount) internal {
        // Make sure that the current balance in the contract is suffecient to perform the ATB.
        uint256 atbAmount = amountToAddToBalance[token];
        if (amount > atbAmount) {
            revert INSUFFICIENT_BALANCE();
        }

        // Update the new outstanding ATB amount.
        amountToAddToBalance[token] = atbAmount - amount;

        // Get the terminal.
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(PROJECT_ID, token);
        if (address(terminal) == address(0)) revert NO_TERMINAL_FOR(PROJECT_ID, token);

        // Perform the `addToBalance`.
        if (token != JBConstants.NATIVE_TOKEN) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            SafeERC20.forceApprove(IERC20(token), address(terminal), amount);

            terminal.addToBalanceOf(PROJECT_ID, token, amount, false, string(""), bytes(""));

            // Sanity check: make sure we transfer the full amount.
            assert(IERC20(token).balanceOf(address(this)) == balanceBefore - amount);
        } else {
            terminal.addToBalanceOf{value: amount}(PROJECT_ID, token, amount, false, string(""), bytes(""));
        }
    }

    /// @notice Redeems the project tokens for the redemption tokens.
    /// @param projectToken the token to redeem.
    /// @param amount the amount of project tokens to redeem.
    /// @param token the token to redeem for.
    /// @param minReceivedTokens the minimum amount of tokens to receive.
    /// @return receivedAmount the amount of tokens received by redeeming.
    function _getBackingAssets(IERC20 projectToken, uint256 amount, address token, uint256 minReceivedTokens)
        internal
        virtual
        returns (uint256 receivedAmount)
    {
        // Get the projectToken total supply.
        uint256 totalSupply = projectToken.totalSupply();

        // Burn the project tokens.
        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).burnTokensOf(
            address(this), PROJECT_ID, amount, string("")
        );

        // Get the primaty terminal of the project for the token.
        IJBRedeemTerminal terminal = IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(PROJECT_ID, token)));

        // Make sure a terminal is configured for the token.
        if (address(terminal) == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Get the accounting context for the token.
        JBAccountingContext memory accountingContext = terminal.accountingContextForTokenOf(PROJECT_ID, token);
        if (accountingContext.decimals == 0 && accountingContext.currency == 0) {
            revert TOKEN_NOT_MAPPED(token);
        }

        uint256 surplus =
            terminal.currentSurplusOf(PROJECT_ID, accountingContext.decimals, accountingContext.currency);

        // TODO: replace with PRB-Math muldiv.
        uint256 backingAssets = amount * surplus / totalSupply;

        // Get the balance before we redeem.
        uint256 balanceBefore = _balanceOf(token, address(this));
        receivedAmount = IBPSuckerDeployerFeeless(DEPLOYER).useAllowanceFeeless(
            PROJECT_ID,
            IJBPayoutTerminal(address(terminal)),
            token,
            accountingContext.currency,
            backingAssets,
            minReceivedTokens
        );

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        assert(receivedAmount == _balanceOf(token, address(this)) - balanceBefore);
    }

    /// @notice builds the hash as its stored in the tree.
    /// @param projectTokenAmount the amount of project tokens redeemed.
    /// @param redemptionTokenAmount the amount of redemptionTokens received.
    /// @param beneficiary the beneficiary of the tokens.
    function _buildTreeHash(uint256 projectTokenAmount, uint256 redemptionTokenAmount, address beneficiary)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(projectTokenAmount, redemptionTokenAmount, beneficiary));
    }

    /// @notice Helper to get the balance for a token of an address.
    /// @param token the token to get the balance for.
    /// @param addr the address to get the token balance of.
    /// @return balance the balance of the address.
    function _balanceOf(address token, address addr) internal view returns (uint256 balance) {
        if (token == JBConstants.NATIVE_TOKEN) {
            return addr.balance;
        }

        return IERC20(token).balanceOf(addr);
    }
}
