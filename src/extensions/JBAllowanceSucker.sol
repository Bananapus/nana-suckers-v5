// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {JBSucker} from "./../JBSucker.sol";
import {IJBSuckerDeployerFeeless} from "../interfaces/IJBSuckerDeployerFeeless.sol";

abstract contract JBAllowanceSucker is JBSucker {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBAllowanceSucker_TokenNotMapped();

    //*********************************************************************//
    // ---------------------- internal functions ------------------------- //
    //*********************************************************************//

    /// @notice Redeems the project tokens for the redemption tokens.
    /// @param projectToken the token to redeem.
    /// @param amount the amount of project tokens to redeem.
    /// @param token the token to redeem for.
    /// @param minReceivedTokens the minimum amount of tokens to receive.
    /// @return receivedAmount the amount of tokens received by redeeming.
    function _pullBackingAssets(IERC20 projectToken, uint256 amount, address token, uint256 minReceivedTokens)
        internal
        virtual
        override
        returns (uint256 receivedAmount)
    {
        // Get the projectToken total supply.
        uint256 totalSupply = projectToken.totalSupply();

        // Burn the project tokens.
        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).burnTokensOf(
            address(this), PROJECT_ID, amount, string("")
        );

        // Get the primary terminal of the project for the token.
        IJBRedeemTerminal terminal = IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(PROJECT_ID, token)));

        // Make sure a terminal is configured for the token.
        if (address(terminal) == address(0)) {
            revert JBAllowanceSucker_TokenNotMapped();
        }

        // Get the accounting context for the token.
        JBAccountingContext memory accountingContext = terminal.accountingContextForTokenOf(PROJECT_ID, token);
        if (accountingContext.decimals == 0 && accountingContext.currency == 0) {
            revert JBAllowanceSucker_TokenNotMapped();
        }

        uint256 surplus =
            terminal.currentSurplusOf(PROJECT_ID, accountingContext.decimals, accountingContext.currency);

        // TODO: replace with PRB-Math muldiv.
        uint256 backingAssets = amount * surplus / totalSupply;

        // Get the balance before we redeem.
        uint256 balanceBefore = _balanceOf(token, address(this));
        receivedAmount = IJBSuckerDeployerFeeless(DEPLOYER).useAllowanceFeeless({
            projectId: PROJECT_ID,
            terminal: IJBPayoutTerminal(address(terminal)),
            token: token,
            currency: accountingContext.currency,
            amount: backingAssets,
            minReceivedTokens: minReceivedTokens
        });

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        // slither-disable-next-line incorrect-equality
        assert(receivedAmount == _balanceOf(token, address(this)) - balanceBefore);
    }
}
