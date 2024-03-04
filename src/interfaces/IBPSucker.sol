// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BPTokenMapping} from "../structs/BPTokenMapping.sol";

interface IBPSucker {
    function isMapped(address token) external view returns (bool);

    function prepare(uint256 projectTokenAmount, address beneficiary, uint256 minTokensReclaimed, address token)
        external;

    function mapToken(BPTokenMapping calldata map) external;

    function mapTokens(BPTokenMapping[] calldata maps) external;

    event NewInboxTreeRoot(address indexed token, uint64 nonce, bytes32 root);

    event RootToRemote(bytes32 indexed root, address indexed terminalToken, uint256 index, uint64 nonce);

    event InsertToOutboxTree(
        address indexed beneficiary,
        address indexed terminalToken,
        bytes32 hashed,
        uint256 index,
        bytes32 root,
        uint256 projectTokenAmount,
        uint256 terminalTokenAmount
    );
}
