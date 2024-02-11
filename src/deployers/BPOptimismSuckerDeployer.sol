// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../BPOptimismSucker.sol";

import {Create2} from "openzeppelin-contracts/contracts/utils/Create2.sol";

contract BPOptimismSuckerDeployer {
    IJBPrices immutable PRICES;
    IJBRulesets immutable RULESETS;
    OPMessenger immutable MESSENGER;
    OpStandardBridge immutable BRIDGE;
    IJBDirectory immutable DIRECTORY;
    IJBTokens immutable TOKENS;
    IJBPermissions immutable PERMISSIONS;
    bytes32 immutable SUCKER_BYTECODE_HASH;

    constructor(
        IJBPrices _prices,
        IJBRulesets _rulesets,
        OPMessenger _messenger,
        OpStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions
    ) {
        PRICES = _prices;
        RULESETS = _rulesets;
        MESSENGER = _messenger;
        BRIDGE = _bridge;
        DIRECTORY = _directory;
        TOKENS = _tokens;
        PERMISSIONS = _permissions;

        SUCKER_BYTECODE_HASH = keccak256(abi.encodePacked(type(BPOptimismSucker).creationCode));
    }

    function createForSender(
        uint256 _localProjectId,
        bytes32 _salt
    ) external returns (address) {
        _salt = keccak256(abi.encodePacked(msg.sender, _salt));
        return address(new BPOptimismSucker{salt: _salt}(
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
    }
}