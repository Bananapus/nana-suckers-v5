// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTokenMapping} from "../structs/JBTokenMapping.sol";

interface IJBSucker {
    event Claimed(
        address beneficiary,
        address token,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        uint256 index,
        bool autoAddedToBalance,
        address caller
    );

    event InsertToOutboxTree(
        address indexed beneficiary,
        address indexed token,
        bytes32 hashed,
        uint256 index,
        bytes32 root,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        address caller
    );

    event NewInboxTreeRoot(address indexed token, uint64 nonce, bytes32 root, address caller);

    event RootToRemote(bytes32 indexed root, address indexed token, uint256 index, uint64 nonce, address caller);

    function PEER() external view returns (address);

    function peerChainID() external view returns (uint256 chainId);

    function isMapped(address token) external view returns (bool);

    function prepare(uint256 projectTokenAmount, address beneficiary, uint256 minTokensReclaimed, address token)
        external;

    function mapToken(JBTokenMapping calldata map) external;

    function mapTokens(JBTokenMapping[] calldata maps) external;
}
