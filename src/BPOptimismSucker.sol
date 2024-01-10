// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {OPMessenger} from "./interfaces/OPMessenger.sol";

import {IJBDirectory} from "juice-contracts-v4/src/interfaces/IJBDirectory.sol";
import {IJBController} from "juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBTokens, IJBToken} from "juice-contracts-v4/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import {IJBRedeemTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBRedeemTerminal.sol";

import {BPSuckQueueItem} from "./structs/BPSuckQueueItem.sol";
import {BPSuckBridgeItem} from "./structs/BPSuckBridgeItem.sol";
import {BPTokenConfig} from "./structs/BPTokenConfig.sol";
import {JBConstants} from "juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBPermissioned, IJBPermissions} from "juice-contracts-v4/src/abstract/JBPermissioned.sol";
import {JBPermissionIds} from "juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

enum SuckingStatus {
    NONE,
    RECEIVED,
    DONE
}

/// @notice A contract that sucks tokens from one chain to another.
/// @dev This implementation is designed to be deployed on two chains that are connected by an OP bridge.
contract BPOptimismSucker is JBPermissioned {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error NOT_PEER();
    error BELOW_MIN_GAS(uint256 _minGas, uint256 _suppliedGas);
    error INVALID_REMOTE();
    error INVALID_AMOUNT();
    error REQUIRE_ISSUED_TOKEN();
    error BENEFICIARY_NOT_ALLOWED();
    error INVALID_SUCK(bytes32 _hash);
    error NO_TERMINAL_FOR(uint256 _projectId, address _token);

    event AddedToQueue(
        address indexed beneficiary,
        address indexed token,
        uint256 tokenAmountAdded,
        uint256 totalBeneficiaryTokenQueue,
        uint256 redemptionTokenAmountAdded,
        uint256 totalBeneficiaryRedemptionTokenQueue
    );

    event BridgeData(
        bytes32 indexed messageHash,
        uint256 nonce,
        address token,
        uint256 tokenAmount,
        BPSuckBridgeItem[] items
    );

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    // TODO: rename items for queue;
    mapping(address _token => mapping(address _beneficiary => BPSuckQueueItem)) public queue;

    mapping(address _token => BPTokenConfig _remoteToken) public token;

    mapping(bytes32 _suckHash => SuckingStatus _status) public message;

    uint256 nonce;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The messenger in use to send messages between the local and remote sucker.
    OPMessenger public immutable OPMESSENGER;

    /// @notice The Juicebox Directory
    IJBDirectory public immutable DIRECTORY;

    /// @notice The Juicebox Tokenstore
    IJBTokens public immutable TOKENS;

    /// @notice The peer sucker on the remote chain.
    address public immutable PEER;

    /// @notice the project ID this sucker is for (on this chain).
    uint256 public immutable PROJECT_ID;

    /// @notice The maximum number of sucks that can get batched.
    uint256 constant MAX_BATCH_SIZE = 6;

    /// @notice The amount of gas the basic xchain call will use.
    uint32 constant MESSENGER_BASE_GAS_LIMIT = 200_000;

    /// @notice The minimum amount of gas an ERC20 bridge can be configured to.
    uint32 constant MESSENGER_ERC20_MIN_GAS_LIMIT = 200_000;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        OPMessenger _messenger,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions,
        address _peer,
        uint256 _projectId
    ) JBPermissioned(_permissions) {
        OPMESSENGER = _messenger;
        DIRECTORY = _directory;
        TOKENS = _tokens;
        PEER = _peer;
        PROJECT_ID = _projectId;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Prepare project tokens (and backing redemption amount) to be bridged to the remote chain.
    /// @param _projectTokenAmount the amount of tokens to move.
    /// @param _beneficiary the recipient of the tokens on the remote chain.
    /// @param _minRedeemedTokens the minimum amount of assets that gets moved.
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
        if(address(_terminal) == address(0) || (_token != JBConstants.NATIVE_TOKEN && token[_token].remoteToken == address(0))){
            revert(); // TODO: fancy revert
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

        // Queue the item.
        _insertIntoQueue(
            _projectTokenAmount,
            _token,
            _redemptionTokenAmount,
            _beneficiary
        );
    }

    /// @notice Bridge funds for one or multiple beneficiaries.
    /// @param _token the token to bridge.
    /// @param _beneficiaries the beneficiaries to bridge the funds for.
    /// @return _messageHash the hash of the message that is being bridged.
    function toRemote(
        address _token,
        address[] calldata _beneficiaries
    ) external returns (bytes32 _messageHash) {
        // TODO: Add logic here to prevent DOS.

        BPSuckBridgeItem[] memory _itemsToBridge = new BPSuckBridgeItem[](_beneficiaries.length);

        uint256 _amountToBridge;
        for(uint256 _i; _i < _beneficiaries.length ; _i++) {
            // Load the item.
            BPSuckQueueItem memory _queueItem = queue[_token][_beneficiaries[_i]];
            // Delete the item from the queue
            delete queue[_token][_beneficiaries[_i]];
            
            _itemsToBridge[_i] = BPSuckBridgeItem({
                beneficiary: _beneficiaries[_i],
                projectTokens: _queueItem.projectTokens
            });

            _amountToBridge += _queueItem.redemptionTokens;
        }

        return _sendItemsOverBridge(_token, _amountToBridge, _itemsToBridge);
    }

    /// @notice Receive from the remote project.
    /// @param _messageHash the hash of the suck message.
    function fromRemote(
        bytes32 _messageHash
    ) external payable {
        // Make sure that the message came from our peer.
        if (msg.sender != address(OPMESSENGER) || OPMESSENGER.xDomainMessageSender() != PEER) {
            revert NOT_PEER();
        }

        // Store the message.
        message[_messageHash] = SuckingStatus.RECEIVED;
    }

    ///.@notice Used to perform the `addToBalance` for the tokens to the project.
    /// @param _token the token to add to the projects balance.
    function executeMessage(
        uint256 _nonce,
        address _token,
        uint256 _redemptionTokenAmount,
        BPSuckBridgeItem[] calldata _items
    ) external {
        bytes32 _hash = _buildMessageHash(_nonce, _token, _redemptionTokenAmount, _items);
        if (message[_hash] != SuckingStatus.RECEIVED) revert INVALID_SUCK(_hash);

        // Update the state of the message
        message[_hash] = SuckingStatus.DONE;

        // Get the terminal.
        IJBTerminal _terminal = DIRECTORY.primaryTerminalOf(PROJECT_ID, _token);
        if(address(_terminal) == address(0)) revert NO_TERMINAL_FOR(PROJECT_ID, _token);

        // Perform the `addToBalance`.
        if(_token != JBConstants.NATIVE_TOKEN) {
            uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
            SafeERC20.forceApprove(IERC20(_token), address(_terminal), _redemptionTokenAmount);

            _terminal.addToBalanceOf(
                PROJECT_ID, _token, _redemptionTokenAmount, false, string(""), bytes("")
            );

            // Sanity check: make sure we transfer the full amount.
            assert(IERC20(_token).balanceOf(address(this)) == _balanceBefore - _redemptionTokenAmount);
        } else {
            _terminal.addToBalanceOf{value: _redemptionTokenAmount}(
                PROJECT_ID, _token, _redemptionTokenAmount, false, string(""), bytes("")
            );
        }

        // Mint the tokens to all the beneficiaries.
        for (uint256 _i = 0; _i < _items.length; ++_i) {
            // Mint to the beneficiary.
            // TODO: try catch this call, so that one reverting mint won't revert the entire queue
            // TODO: Bulk mint here and then send the tokens to the beneficiaries might be more effecient.
            IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).mintTokensOf(
                PROJECT_ID, _items[_i].projectTokens, _items[_i].beneficiary, "", false
            );
        }
    }

    /// @notice Links an ERC20 token on the local chain to an ERC20 on the remote chain.
    function configureToken(address _token, BPTokenConfig calldata _config) external {
        // As misconfiguration can lead to loss of funds we enforce a reasonable minimum.
        if(_config.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT) 
            revert BELOW_MIN_GAS(MESSENGER_ERC20_MIN_GAS_LIMIT, _config.minGas);

        // Access control.
        _requirePermissionFrom(
            DIRECTORY.PROJECTS().ownerOf(PROJECT_ID), PROJECT_ID, JBPermissionIds.QUEUE_RULESETS
        );

        token[_token] = _config;
    }

    /// @notice used to receive the redemption ETH.
    receive() external payable {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    function _insertIntoQueue(
        uint256 _projectTokenAmount,
        address _redemptionToken,
        uint256 _redemptionTokenAmount,
        address _beneficiary
    ) internal {
        // Increase the amount that is in the queue for the beneficiary and the specific redemption token.
        BPSuckQueueItem memory _beforeQueue = queue[_redemptionToken][_beneficiary];
        BPSuckQueueItem memory _updatedQueue = BPSuckQueueItem({
            projectTokens: _beforeQueue.projectTokens + _projectTokenAmount,
            redemptionTokens: _beforeQueue.redemptionTokens + _redemptionTokenAmount
        });

        queue[_redemptionToken][_beneficiary] = _updatedQueue;

        emit AddedToQueue({
            beneficiary: _beneficiary,
            token: _redemptionToken,
            tokenAmountAdded: _projectTokenAmount,
            totalBeneficiaryTokenQueue: _updatedQueue.projectTokens,
            redemptionTokenAmountAdded: _redemptionTokenAmount,
            totalBeneficiaryRedemptionTokenQueue: _updatedQueue.redemptionTokens
        });
    }

    /// @notice Works a specific queue, sending the sucks to the peer on the remote chain.
    /// @param _token the queue of the token being worked.
    /// @param _tokenAmount the amount of tokens to bridge.
    /// @param _itemsToBridge the items to bridge.
    function _sendItemsOverBridge(
        address _token,
        uint256 _tokenAmount,
        BPSuckBridgeItem[] memory _itemsToBridge
    ) internal virtual returns (bytes32 _messageHash) {
        uint256 _nativeValue;
        address _remoteToken;
        if(_token != JBConstants.NATIVE_TOKEN){
            BPTokenConfig memory _tokenConfig = token[_token];
            _remoteToken = _tokenConfig.remoteToken;

            // Bridge the tokens to the payer address.
            OPMESSENGER.bridgeERC20To({
                localToken: _token,
                remoteToken: _tokenConfig.remoteToken,
                to: PEER,
                amount: _tokenAmount,
                minGasLimit: _tokenConfig.minGas,
                extraData: bytes('')
            });
        } else {
            _remoteToken = JBConstants.NATIVE_TOKEN;
            _nativeValue = _tokenAmount;
        }
        uint256 _nonce = nonce++;
        _messageHash = _buildMessageHash(
            _nonce,
            _remoteToken,
            _tokenAmount,
            _itemsToBridge
        );

        // Send the messenger to the peer with the redeemed ETH.
        OPMESSENGER.sendMessage{value: _nativeValue}(
            PEER,
            abi.encodeWithSelector(
                BPOptimismSucker.fromRemote.selector,
                _messageHash
            ),
            MESSENGER_BASE_GAS_LIMIT
        );

        emit BridgeData({
            messageHash: _messageHash,
            nonce: _nonce,
            token: _token,
            tokenAmount: _tokenAmount,
            items: _itemsToBridge
        });
    }

    function _buildMessageHash(
        uint256 _nonce,
        address _token,
        uint256 _tokenAmount,
        BPSuckBridgeItem[] memory _items
    ) internal pure returns (bytes32) {
       return keccak256(abi.encode(
            _nonce,
            _token,
            _tokenAmount,
            _items
       )) ;
    }

    function _balanceOf(
        address _token,
        address _address
    ) internal view returns (uint256 _balance){
        if(_token == JBConstants.NATIVE_TOKEN)
            return _address.balance;

        return IERC20(_token).balanceOf(_address);
    }
}
