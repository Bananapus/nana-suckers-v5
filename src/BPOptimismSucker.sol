// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {OPMessenger} from "./interfaces/OPMessenger.sol";

import {IJBDirectory} from "juice-contracts-v4/src/interfaces/IJBDirectory.sol";
import {IJBController} from "juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBTokens, IJBToken} from "juice-contracts-v4/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import {IJBRedeemTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBRedeemTerminal.sol";

import {BPSuckerData, BPSuckQueueItem} from "./structs/BPSuckerData.sol";
import {JBConstants} from "juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBPermissioned, IJBPermissions} from "juice-contracts-v4/src/abstract/JBPermissioned.sol";
import {JBPermissionIds} from "juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BPProjectPayer} from "./BPProjectPayer.sol";

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
    error INVALID_REMOTE();
    error INVALID_AMOUNT();
    error REQUIRE_ISSUED_TOKEN();
    error BENEFICIARY_NOT_ALLOWED();
    error INVALID_SUCK(bytes32 _hash);
    error NO_TERMINAL_FOR(uint256 _projectId, address _token);

    event BRIDGE_DATA(
        uint256 _nonce,
        address _token,
        uint256 _redemptionTokenAmount,
        BPSuckQueueItem[] _items
    );

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    mapping(address _token => BPSuckerData _queue) queue;

    mapping(address _localToken => address _remoteToken) token;

    mapping(bytes32 _suckHash => SuckingStatus _status) message;

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

    uint256 public immutable PROJECT_ID;

    /// @notice The maximum number of sucks that can get batched.
    uint256 constant MAX_BATCH_SIZE = 6;

    /// @notice The amount of gas the basic xchain call will use.
    uint32 constant MESSENGER_BASE_GAS_LIMIT = 500_000;

    /// @notice the amount of gas that each queue item is allowed to use.
    uint32 constant MESSENGER_QUEUE_ITEM_GAS_LIMIT = 100_000;

    uint32 constant MESSENGER_ERC20_BRIDGE_GAS_LIMIT = 200_000;

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

    /// @notice Send to the remote project.
    /// @notice _localProjectId the Id of the project to move the tokens for.
    /// @notice _projectTokenAmount the amount of tokens to move.
    /// @notice _beneficiary the recipient of the tokens on the remote chain.
    /// @notice _minRedeemedTokens the minimum amount of assets that gets moved.
    /// @notice _forceSend whether or not to force the send, even if the queue is not full.
    function toRemote(
        uint256 _localProjectId,
        uint256 _projectTokenAmount,
        address _beneficiary,
        uint256 _minRedeemedTokens,
        address _token,
        bool _forceSend
    ) external {
        // Make sure the beneficiary is not the zero address, as this would revert when minting on the remote chain.
        if (_beneficiary == address(0)) {
            revert BENEFICIARY_NOT_ALLOWED();
        }

        // Get the terminal we will use to redeem the tokens.
        IJBRedeemTerminal _terminal =
            IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(_localProjectId, _token)));

        // Make sure that the token is configured to be sucked (both is redeemable and is mapped to a remote token)
        if(address(_terminal) == address(0) || (_token != JBConstants.NATIVE_TOKEN && token[_token] == address(0))){
            revert(); // TODO: fancy revert
        }

        // Get the token for the project.
        IERC20 _projectToken = IERC20(address(TOKENS.tokenOf(_localProjectId)));
        if (address(_projectToken) == address(0)) {
            revert REQUIRE_ISSUED_TOKEN();
        }

        // Transfer the tokens to this contract.
        _projectToken.transferFrom(msg.sender, address(this), _projectTokenAmount);

        // Approve the terminal.
        _projectToken.approve(address(_terminal), _projectTokenAmount);

        // Perform the redemption.
        uint256 _balanceBefore = address(this).balance;
        uint256 _redemptionTokenAmount = _terminal.redeemTokensOf(
            address(this),
            _localProjectId,
            _token,
            _projectTokenAmount,
            _minRedeemedTokens,
            payable(address(this)),
            bytes("")
        );

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        assert(_redemptionTokenAmount == address(this).balance - _balanceBefore);

        // Queue the item.
        _queueItem(
             _projectTokenAmount, _token, _redemptionTokenAmount, _beneficiary, _forceSend
        );
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
        BPSuckQueueItem[] calldata _items
    ) external {
        bytes32 _hash = _buildSuckHash(_nonce, _token, _redemptionTokenAmount, _items);
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
                PROJECT_ID, _items[_i].tokensRedeemed, _items[_i].beneficiary, "", false
            );
        }
    }

    /// @notice Links an ERC20 token on the local chain to an ERC20 on the remote chain.
    function linkTokens(uint256 _localProjectId, address _localToken, address _remoteToken) external {
        // Access control.
        _requirePermissionFrom(
            DIRECTORY.PROJECTS().ownerOf(_localProjectId), _localProjectId, JBPermissionIds.QUEUE_RULESETS
        );

        token[_localToken] = _remoteToken;
    }

    /// @notice used to receive the redemption ETH.
    receive() external payable {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    function _queueItem(
        uint256 _projectTokenAmount,
        address _token,
        uint256 _redemptionTokenAmount,
        address _beneficiary,
        bool _forceSend
    ) internal {
        // Store the queued item
        BPSuckerData storage _queue = queue[_token];
        _queue.redemptionAmount += _redemptionTokenAmount;
        _queue.items.push(BPSuckQueueItem({beneficiary: _beneficiary, tokensRedeemed: _projectTokenAmount}));

        // Check if we should work the queue or if we only needed to append this suck to the queue.
        if (_forceSend || _queue.items.length == MAX_BATCH_SIZE) {
            _workQueue(_token);
        }
    }

    /// @notice Works a specific queue, sending the sucks to the peer on the remote chain.
    /// @param _token the queue of the token being worked.
    function _workQueue(address _token) internal {
        // Load the queue.
        BPSuckerData memory _queue = queue[_token];

        // Clear them from storage
        delete queue[_token];

        uint256 _nativeValue;
        address _remoteToken;
        if(_token != JBConstants.NATIVE_TOKEN){
            // Bridge the tokens to the payer address.
            _remoteToken = token[_token];
            OPMESSENGER.bridgeERC20To({
                localToken: _token,
                remoteToken: _remoteToken,
                to: PEER,
                amount: _queue.redemptionAmount,
                minGasLimit: MESSENGER_ERC20_BRIDGE_GAS_LIMIT,
                extraData: bytes('')
            });
        } else {
            _remoteToken = JBConstants.NATIVE_TOKEN;
            _nativeValue = _queue.redemptionAmount;
        }

        bytes32 _suckHash = _buildAndEmitSuckHash(
            nonce++,
            _remoteToken,
            _queue.redemptionAmount,
            _queue.items
        );

        // Calculate the needed gas limit for this specific queue.
        uint32 _gasLimit = MESSENGER_BASE_GAS_LIMIT + uint32(_queue.items.length * MESSENGER_QUEUE_ITEM_GAS_LIMIT);

        // Send the messenger to the peer with the redeemed ETH.
        OPMESSENGER.sendMessage{value: _nativeValue}(
            PEER,
            abi.encodeWithSelector(
                BPOptimismSucker.fromRemote.selector,
                _token,
                _suckHash
            ),
            _gasLimit
        );
    }

    function _buildAndEmitSuckHash(
        uint256 _nonce,
        address _token,
        uint256 _redemptionTokenAmount,
        BPSuckQueueItem[] memory _items
    ) internal returns (bytes32)  {
        emit BRIDGE_DATA(
            _nonce,
            _token,
            _redemptionTokenAmount,
            _items
        );

        return _buildSuckHash(
            _nonce,
            _token,
            _redemptionTokenAmount,
            _items
        );
    }

    function _buildSuckHash(
        uint256 _nonce,
        address _token,
        uint256 _redemptionTokenAmount,
        BPSuckQueueItem[] memory _items
    ) internal pure returns (bytes32) {
       return keccak256(abi.encode(
            _nonce,
            _token,
            _redemptionTokenAmount,
            _items
       )) ;
    }
}
