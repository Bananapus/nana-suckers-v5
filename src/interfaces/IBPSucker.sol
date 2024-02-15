// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BPTokenConfig} from "../structs/BPTokenConfig.sol";

interface IBPSucker {
    /// @notice checks if a token is supported by the sucker.
    /// @param _token the token to check.
    /// @return _supported true if the token is supported.
    function isTokenSupported(address _token) external view returns (bool);

    /// @notice Prepare project tokens (and backing redemption amount) to be bridged to the remote chain.
    /// @param _projectTokenAmount the amount of tokens to move.
    /// @param _beneficiary the recipient of the tokens on the remote chain.
    /// @param _minRedeemedTokens the minimum amount of tokens that must be redeemed against the project tokens.
    /// @param _token the token to redeem for.
    function bridge(uint256 _projectTokenAmount, address _beneficiary, uint256 _minRedeemedTokens, address _token)
        external;

    /// @notice Links an ERC20 token on the local chain to an ERC20 on the remote chain.
    /// @param _config the configuration details.
    function configureToken(BPTokenConfig calldata _config) external payable;
    function configureTokens(BPTokenConfig[] calldata _config) external payable;
}