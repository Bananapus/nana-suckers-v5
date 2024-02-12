// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../BPOptimismSucker.sol";

import {Create2} from "openzeppelin-contracts/contracts/utils/Create2.sol";

import {JBPermissioned, IJBPermissions} from "juice-contracts-v4/src/abstract/JBPermissioned.sol";
import {IJBPayoutTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBPayoutTerminal.sol";

contract BPOptimismSuckerDeployer is JBPermissioned {

    error ONLY_SUCKERS();

    IJBPrices immutable PRICES;
    IJBRulesets immutable RULESETS;
    OPMessenger immutable MESSENGER;
    OpStandardBridge immutable BRIDGE;
    IJBDirectory immutable DIRECTORY;
    IJBTokens immutable TOKENS;
    bytes32 immutable SUCKER_BYTECODE_HASH;

    mapping(address => bool) public isSucker;

    constructor(
        IJBPrices _prices,
        IJBRulesets _rulesets,
        OPMessenger _messenger,
        OpStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions
    ) JBPermissioned(_permissions) {
        PRICES = _prices;
        RULESETS = _rulesets;
        MESSENGER = _messenger;
        BRIDGE = _bridge;
        DIRECTORY = _directory;
        TOKENS = _tokens;

        SUCKER_BYTECODE_HASH = keccak256(abi.encodePacked(type(BPOptimismSucker).creationCode));
    }

    function createForSender(
        uint256 _localProjectId,
        bytes32 _salt
    ) external returns (address _sucker) {
        _salt = keccak256(abi.encodePacked(msg.sender, _salt));
        _sucker = address(new BPOptimismSucker{salt: _salt}(
            PRICES,
            RULESETS,
            MESSENGER,
            BRIDGE,
            DIRECTORY,
            TOKENS,
            PERMISSIONS,
            address(0),
            _localProjectId
        ));
        isSucker[_sucker] = true;
    }

    /// @notice Use the allowance of a project witgout paying exit fees.
    /// @dev This function can only be called by suckers deploted by this contract, and only if the project owner has given the specicifc sucker permission to use the allowance.
    /// @dev This is not necesarily feeless, as it still requires JBDAO to mark this as feeless first. 
    /// @param _projectId the project id.
    /// @param _terminal the terminal to use.
    /// @param _token the token to use the allowance of.
    /// @param _currency the currency the amount is denominated in.
    /// @param _amount the amount to get from the terminal, denomated in the currency.
    /// @param _minReceivedTokens the minimum amount of tokens to receive.
    /// @return the amount of tokens received.
    function useAllowanceFeeless(
        uint256 _projectId,
        IJBPayoutTerminal _terminal,
        address _token,
        uint32 _currency,
        uint256 _amount,
        uint256 _minReceivedTokens
    ) external returns (uint256) {
        // Make sure the caller is a sucker.
        if(!isSucker[msg.sender]) 
            revert ONLY_SUCKERS();

         // Access control: Only allowed suckes can use the allowance.
        _requirePermissionFrom(
            DIRECTORY.PROJECTS().ownerOf(_projectId),
            _projectId,
            JBPermissionIds.USE_ALLOWANCE
        );
        
        // Use the allowance.
        return _terminal.useAllowanceOf(
            _projectId,
            _token,
            _amount,
            _currency,
            _minReceivedTokens,
            payable(address(msg.sender)),
            string("")
        );
    }
}