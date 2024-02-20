// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BPTokenMapConfig} from "../structs/BPTokenMapConfig.sol";

interface IBPSucker {
    function isSupported(address token) external view returns (bool);

    /// @notice Prepare project tokens (and backing redemption amount) to be bridged to the remote chain.
    /// @param _projectTokenAmount the amount of tokens to move.
    /// @param _beneficiary the recipient of the tokens on the remote chain.
    /// @param _minRedeemedTokens the minimum amount of tokens that must be redeemed against the project tokens.
    /// @param _token the token to redeem for.
    function prepare(uint256 _projectTokenAmount, address _beneficiary, uint256 _minRedeemedTokens, address _token)
        external;

    /// @notice Links an ERC20 token on the local chain to an ERC20 on the remote chain.
    /// @param _config the configuration details.
    function mapToken(BPTokenMapConfig calldata _config) external payable;
    function mapTokens(BPTokenMapConfig[] calldata _config) external payable;
}