// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBDirectory} from "juice-contracts-v4/src/interfaces/IJBDirectory.sol";
import {IJBController} from "juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBTokens, IJBToken} from "juice-contracts-v4/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import {IJBRedeemTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBRedeemTerminal.sol";

import {MerkleLib} from "./utils/MerkleLib.sol";

// import {BPSuckQueueItem} from "./structs/BPSuckQueueItem.sol";
// import {BPSuckBridgeItem} from "./structs/BPSuckBridgeItem.sol";
import {BPTokenConfig} from "./structs/BPTokenConfig.sol";
import {JBConstants} from "juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBPermissioned, IJBPermissions} from "juice-contracts-v4/src/abstract/JBPermissioned.sol";
import {JBPermissionIds} from "juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/structs/BitMaps.sol";

/// @notice A contract that sucks tokens from one chain to another.
/// @dev This implementation is designed to be deployed on two chains that are connected by an OP bridge.
abstract contract BPSucker is JBPermissioned {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    uint256 internal constant TREE_DEPTH = 32;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error NOT_PEER();
    error BELOW_MIN_GAS(uint256 _minGas, uint256 _suppliedGas);
    error REQUIRE_ISSUED_TOKEN();
    error BENEFICIARY_NOT_ALLOWED();
    error NO_TERMINAL_FOR(uint256 _projectId, address _token);
    error INVALID_PROOF(bytes32 _expectedRoot, bytes32 _proofRoot);
    error ALREADY_EXECUTED(uint256 _index);
    error CURRENT_BALANCE_INSUFFECIENT();
    error TOKEN_NOT_CONFIGURED(address _token);
    error ON_DEMAND_NOT_ALLOWED();
    error UNEXPECTED_MSG_VALUE();

    event NewRoot(
        address indexed token,
        uint64 nonce,
        bytes32 root
    );

    event insertedIntoTree(
        address indexed beneficiary,
        address indexed redemptionToken,
        bytes32 hashed,
        uint256 index,
        bytes32 root,
        uint256 projectTokenAmount,
        uint256 redemptionTokenAmount
    );

    struct OutboxTree {
        uint64 nonce;
        uint256 balance;
        MerkleLib.Tree tree;
    }

    struct MessageRoot{
        /// @notice the token that the root is for.
        address token;
        /// @notice the amount of tokens being send.
        uint256 amount;
        /// @notice the tree root for the token.
        RemoteRoot remoteRoot;
    }

    struct RemoteRoot {
        /// @notice tracks the nonce of the tree, we only allow increased nonces.
        uint64 nonce;
        /// @notice the root of the tree.
        bytes32 root;
    }

    struct Leaf {
        uint256 index;
        address beneficiary;
        uint256 projectTokenAmount;
        uint256 redemptionTokenAmount;
    }

    enum AddToBalanceMode {
        ON_DEMAND,
        ON_CLAIM
    }

    struct Claim {
        address token;
        Leaf leaf;
        bytes32[TREE_DEPTH] proof;
    }

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice the outbox tree.
    mapping(address _token => OutboxTree) public outbox;

    /// @notice the inbox trees.
    mapping(address _token => RemoteRoot _root) public inbox;

    /// @notice tracks outstanding token amount to be added to the projects balance.
    mapping(address _token => uint256 _amount) public outstandingATB;

    /// @notice configuration of each token.
    mapping(address _token => BPTokenConfig _remoteToken) public token;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Configuration option regarding when `addToBalance` gets called.
    AddToBalanceMode public immutable ATB_MODE; 

    /// @notice The Juicebox Directory
    IJBDirectory public immutable DIRECTORY;

    /// @notice The Juicebox Tokenstore
    IJBTokens public immutable TOKENS;

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
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions,
        address _peer,
        uint256 _projectId
    ) JBPermissioned(_permissions) {
        DIRECTORY = _directory;
        TOKENS = _tokens;
        PEER = _peer == address(0) ? address(this) : _peer;
        PROJECT_ID = _projectId;

        // sanity check: make sure equal depth tree is configured.
        assert(MerkleLib.TREE_DEPTH == TREE_DEPTH);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Prepare project tokens (and backing redemption amount) to be bridged to the remote chain.
    /// @param _projectTokenAmount the amount of tokens to move.
    /// @param _beneficiary the recipient of the tokens on the remote chain.
    /// @param _minRedeemedTokens the minimum amount of assets that gets moved.
    /// @param _token the token to redeem for.
    function bridge(
        uint256 _projectTokenAmount,
        address _beneficiary,
        uint256 _minRedeemedTokens,
        address _token
    ) external {
        // Make sure the beneficiary is not the zero address, as this would revert when minting on the remote chain.
        if (_beneficiary == address(0)) {
            revert BENEFICIARY_NOT_ALLOWED();
        }

        // Get the terminal we will use to redeem the tokens.
        IJBRedeemTerminal _terminal =
            IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(PROJECT_ID, _token)));

        // Make sure that the token is configured to be sucked (both is redeemable and is mapped to a remote token)
        if(address(_terminal) == address(0) || token[_token].remoteToken == address(0)){
            revert TOKEN_NOT_CONFIGURED(_token);
        }

        // Get the token for the project.
        IERC20 _projectToken = IERC20(address(TOKENS.tokenOf(PROJECT_ID)));
        if (address(_projectToken) == address(0)) {
            revert REQUIRE_ISSUED_TOKEN();
        }

        // Transfer the tokens to this contract.
        _projectToken.transferFrom(msg.sender, address(this), _projectTokenAmount);

        // Approve the terminal.
        _projectToken.approve(address(_terminal), _projectTokenAmount);

        // Perform the redemption.
        uint256 _balanceBefore = _balanceOf(_token, address(this));
        uint256 _redemptionTokenAmount = _terminal.redeemTokensOf(
            address(this),
            PROJECT_ID,
            _token,
            _projectTokenAmount,
            _minRedeemedTokens,
            payable(address(this)),
            bytes("")
        );

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        assert(_redemptionTokenAmount == _balanceOf(_token, address(this)) - _balanceBefore);

        // Insert the item.
        _insertIntoTree(
            _projectTokenAmount,
            _token,
            _redemptionTokenAmount,
            _beneficiary
        );
    }

    /// @notice Bridge funds for one or multiple beneficiaries.
    /// @param _token the token to bridge the tree for.
    function toRemote(
        address _token
    ) external payable {
        // TODO: Add some way to prevent spam.
        BPTokenConfig memory _tokenConfig = token[_token];

        // Require that the min amount being bridged is enough.
        if(outbox[_token].balance < _tokenConfig.minBridgeAmount)
            revert();

        // Send the root to the remote.
        _sendRoot(
            _token,
            _tokenConfig
        );
    }

    /// @notice Receive from the remote project.
    /// @dev can only be called by the OP messenger and with messages from the PEER.
    /// @param _root the root and all the information regarding it.
    function fromRemote(
        MessageRoot calldata _root
    ) external payable {
        // Make sure that the message came from our peer.
        if (!_isRemotePeer(msg.sender)) {
            revert NOT_PEER();
        }

        // Increment the outstanding ATB amount with the amount being bridged.
        outstandingATB[_root.token] += _root.amount;

        // If the nonce is a newer one than we already have we update it.
        // We can't revert in the case that this is a native token transfer
        // otherwise we would lose the native tokens.
        if(_root.remoteRoot.nonce > inbox[_root.token].nonce) {
            inbox[_root.token] = _root.remoteRoot;
            emit NewRoot(_root.token, _root.remoteRoot.nonce, _root.remoteRoot.root);
        }
    }

    /// @notice Performs a claim.
    /// @param _claim The data for the claim.
    function claim(
        Claim calldata _claim
    ) public {
        // Attempt to validate proof.
        _validate({
            _projectTokenAmount: _claim.leaf.projectTokenAmount,
            _redemptionToken: _claim.token,
            _redemptionTokenAmount: _claim.leaf.redemptionTokenAmount,
            _beneficiary: _claim.leaf.beneficiary,
            _index: _claim.leaf.index,
            _leaves: _claim.proof
        });

        // Perform the add to balance if this sucker is configured to perform it on claim.
        if(ATB_MODE == AddToBalanceMode.ON_CLAIM)
            _addToBalance(_claim.token, _claim.leaf.redemptionTokenAmount);

        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).mintTokensOf(
            PROJECT_ID, _claim.leaf.projectTokenAmount, _claim.leaf.beneficiary, "", false
        );
    }

    /// @notice Performs multiple claims.
    /// @param _claims The data for the claims.
    function claim(
        Claim[] calldata _claims
    ) external {
        for (uint256 _i = 0; _i < _claims.length; _i++) {
            claim(_claims[_i]);
        }
    }

    /// @notice Adds the redeemed funds to the projects terminal. Can only be used if AddToBalanceMode is ON_DEMAND.
    /// @param _token The token to add to the terminal.
    function claimToBalance(
        address _token
    ) external {
        if(ATB_MODE != AddToBalanceMode.ON_DEMAND)
            revert ON_DEMAND_NOT_ALLOWED();
        
        // Add entire outstanding amount to the projects balance.
        _addToBalance(_token, outstandingATB[_token]);
    }

    /// @notice Links an ERC20 token on the local chain to an ERC20 on the remote chain.
    /// @param _token the token to configure.
    /// @param _config the configuration details.
    function configureToken(address _token, BPTokenConfig calldata _config) external payable {
        bool _isNative = _token == JBConstants.NATIVE_TOKEN;

        // If the native token is being configured then the remoteToken has to also be the native token.
        // Unless we are disabling native token bridging, then it can also be 0.
        if (_isNative && _config.remoteToken != JBConstants.NATIVE_TOKEN && _config.remoteToken != address(0))
            revert();
            
        // As misconfiguration can lead to loss of funds we enforce a reasonable minimum.
        if(_config.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && !_isNative) 
            revert BELOW_MIN_GAS(MESSENGER_ERC20_MIN_GAS_LIMIT, _config.minGas);

        // Access control.
        _requirePermissionFrom(
            DIRECTORY.PROJECTS().ownerOf(PROJECT_ID), PROJECT_ID, JBPermissionIds.QUEUE_RULESETS
        );

        // If we have a remaining balance in the outbox. 
        // We send a final bridge before disabling so all users can exit with their funds.
        if(
            _config.remoteToken == address(0) &&
            outbox[_token].balance != 0
        ) _sendRoot(_token, token[_token]);

        token[_token] = _config;
    }

    /// @notice used to receive the redemption ETH.
    receive() external payable {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice inserts a new redemption into the sparse-merkle-tree
    /// @param _projectTokenAmount the amount of project tokens redeemed.
    /// @param _redemptionToken the token that the project tokens were redeemed for.
    /// @param _redemptionTokenAmount the amount of redemptionTokens received.
    /// @param _beneficiary the beneficiary of the tokens.
    function _insertIntoTree(
        uint256 _projectTokenAmount,
        address _redemptionToken,
        uint256 _redemptionTokenAmount,
        address _beneficiary
    ) internal {
        bytes32 _hash = _buildTreeHash(
            _projectTokenAmount,
            _redemptionTokenAmount,
            _beneficiary
        );

        // Insert the item into the tree.
        MerkleLib.Tree memory _tree = outbox[_redemptionToken].tree.insert(
            _hash
        );

        // Update the outbox.
        outbox[_redemptionToken].tree = _tree;
        outbox[_redemptionToken].balance += _redemptionTokenAmount;

        emit insertedIntoTree(
            _beneficiary,
            _redemptionToken,
            _hash,
            _tree.count - 1, // -1 since we want the index.
            outbox[_redemptionToken].tree.root(),
            _projectTokenAmount,
            _redemptionTokenAmount
        );
    }

    /// @notice Send the root to the remote peer.
    /// @dev Call may have a `msg.value`, require it to be `0` if its not needed.
    /// @param _token the token to bridge for.
    /// @param _tokenConfig the config for the token to send.
    function _sendRoot(
        address _token,
        BPTokenConfig memory _tokenConfig
    ) internal virtual;

    /// @notice checks if the _sender (msg.sender) is a valid representative of the remote peer. 
    /// @param _sender the message sender.
    function _isRemotePeer(
        address _sender
    ) internal virtual returns (bool _valid);
    
    /// @notice validates a leaf as being in the smt and registers as being redeemed.
    /// @dev Reverts if invalid.
    /// @param _projectTokenAmount the amount of project tokens redeemed.
    /// @param _redemptionToken the token that the project tokens were redeemed for.
    /// @param _redemptionTokenAmount the amount of redemptionTokens received.
    /// @param _beneficiary the beneficiary of the tokens.
    /// @param _index the index of the leaf in the tree.
    /// @param _leaves the leaves that proof the existence in the tree.
    function _validate(
        uint256 _projectTokenAmount,
        address _redemptionToken,
        uint256 _redemptionTokenAmount,
        address _beneficiary,
        uint256 _index,
        bytes32[TREE_DEPTH] calldata _leaves
    ) internal {
        // Make sure the item has not been executed before.
        if(executed[_redemptionToken].get(_index))
            revert ALREADY_EXECUTED(_index);

        // Toggle it as being executed now.
        executed[_redemptionToken].set(_index);

        // Calculate the root from the proof.
        bytes32 _root = MerkleLib.branchRoot({
            _item: _buildTreeHash(
                    _projectTokenAmount,
                    _redemptionTokenAmount,
                    _beneficiary
                ),
            _branch: _leaves,
            _index: _index
        });

        // Compare the root.
        if(_root != inbox[_redemptionToken].root)
            revert INVALID_PROOF(inbox[_redemptionToken].root, _root);
    }

    /// @notice Adds funds to the projects balance.
    /// @param _token the token to add.
    /// @param _amount the amount of the token to add.
    function _addToBalance(
        address _token,
        uint256 _amount
    ) internal {
        // Make sure that the current balance in the contract is suffecient to perform the ATB.
        uint256 _atbAmount = outstandingATB[_token];
        if(_amount > _atbAmount)
            revert CURRENT_BALANCE_INSUFFECIENT();

        // Update the new outstanding ATB amount.
        outstandingATB[_token] = _atbAmount - _amount;

        // Get the terminal.
        IJBTerminal _terminal = DIRECTORY.primaryTerminalOf(PROJECT_ID, _token);
        if(address(_terminal) == address(0)) revert NO_TERMINAL_FOR(PROJECT_ID, _token);

        // Perform the `addToBalance`.
        if(_token != JBConstants.NATIVE_TOKEN) {
            uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
            SafeERC20.forceApprove(IERC20(_token), address(_terminal), _amount);

            _terminal.addToBalanceOf(
                PROJECT_ID, _token, _amount, false, string(""), bytes("")
            );

            // Sanity check: make sure we transfer the full amount.
            assert(IERC20(_token).balanceOf(address(this)) == _balanceBefore - _amount);
        } else {
            _terminal.addToBalanceOf{value: _amount}(
                PROJECT_ID, _token, _amount, false, string(""), bytes("")
            );
        }
    }

    /// @notice builds the hash as its stored in the tree.
    /// @param _projectTokenAmount the amount of project tokens redeemed.
    /// @param _redemptionTokenAmount the amount of redemptionTokens received.
    /// @param _beneficiary the beneficiary of the tokens.
    function _buildTreeHash(
        uint256 _projectTokenAmount,
        uint256 _redemptionTokenAmount,
        address _beneficiary
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _projectTokenAmount,
            _redemptionTokenAmount,
            _beneficiary
        ));
    }

    /// @notice Helper to get the balance for a token of an address.
    /// @param _token the token to get the balance for.
    /// @param _address the address to get the token balance of.
    /// @return _balance the balance of the address.
    function _balanceOf(
        address _token,
        address _address
    ) internal view returns (uint256 _balance){
        if(_token == JBConstants.NATIVE_TOKEN)
            return _address.balance;

        return IERC20(_token).balanceOf(_address);
    }
}
