// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBPayHook, JBAfterPayRecordedContext} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {JBRulesetMetadataResolver} from "@bananapus/core/src/libraries/JBRulesetMetadataResolver.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeRedeemRecordedContext} from "@bananapus/core/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBRedeemHookSpecification} from "@bananapus/core/src/structs/JBRedeemHookSpecification.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import "./BPSucker.sol";

/// @notice A pay hook which allows the minting of tokens on a remote chain upon payment through a `BPSucker`.
abstract contract BPSuckerHook is BPSucker, ERC165, IJBRulesetDataHook, IJBPayHook {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    error NOT_ALLOWED();
    error INVALID_REMOTE_PROJECT_ID(uint256 expected, uint256 received);

    /// @notice The contract storing and managing project rulesets.
    IJBRulesets public immutable RULESETS;

    /// @notice The contract that exposes price feeds.
    IJBPrices public immutable PRICES;

    constructor(IJBPrices prices, IJBRulesets rulesets) {
        PRICES = prices;
        RULESETS = rulesets;
    }

    /// @notice If the project being paid has a remote token set up for the token being paid in, return a weight of zero and this contract as the pay hook.
    /// @dev This data is provided to the terminal's `pay(...)` function.
    /// @param context The context passed to this data hook by the `pay(...)` function as a `JBBeforePayRecordedContext`
    /// struct.
    /// @return weight The new `weight` to use, overriding the ruleset's `weight`.
    /// @return hookSpecifications The amount and data to send to a pay hook instead of adding to the terminal's balance.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // If the payment is not for this hook's project, revert.
        if (context.projectId != PROJECT_ID) revert INVALID_REMOTE_PROJECT_ID(PROJECT_ID, context.projectId);

        // Get the token being paid in.
        address token = context.amount.token;

        // If there isn't a remote token for the token being paid in, or if the terminal doesn't support the redeem terminal interface, return the information as-is.
        if (
            remoteTokenFor[token].addr == address(0)
                && !ERC165Checker.supportsInterface(address(context.terminal), type(IJBRedeemTerminal).interfaceId)
        ) {
            return (context.weight, new JBPayHookSpecification[](0));
        }

        // Otherwise, return a weight of zero and this contract as the pay hook (allowing us to mint on the remote chain).
        hookSpecifications = new JBPayHookSpecification[](1);
        hookSpecifications[0] = JBPayHookSpecification({hook: IJBPayHook(address(this)), amount: 0, metadata: ""});

        return (0, hookSpecifications);
    }

    function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable {
        // If the caller is not the project's terminal, revert.
        if (!DIRECTORY.isTerminalOf(context.projectId, IJBTerminal(msg.sender))) revert NOT_ALLOWED();

        // Get the project's ruleset.
        JBRuleset memory ruleset = RULESETS.getRulesetOf(context.projectId, context.rulesetId);

        // Calculate the number of project tokens that would be minted by this payment.
        uint256 weightRatio = context.amount.currency == ruleset.baseCurrency()
            ? 10 ** context.amount.decimals
            : PRICES.pricePerUnitOf({
                projectId: context.projectId,
                pricingCurrency: context.amount.currency,
                unitCurrency: ruleset.baseCurrency(),
                decimals: context.amount.decimals
            });

        uint256 tokenCount = mulDiv(context.amount.value, context.weight, weightRatio);

        // Get the project's token.
        IERC20 projectToken = IERC20(address(TOKENS.tokenOf(context.projectId)));

        // Get this contract's project token balance.
        uint256 projectTokenBalanceBefore = projectToken.balanceOf(address(this));

        // Mint the calculated number of project tokens to this address.
        uint256 beneficiaryTokenCount = IJBController(address(DIRECTORY.controllerOf(context.projectId))).mintTokensOf({
            projectId: context.projectId,
            tokenCount: tokenCount,
            beneficiary: address(this),
            memo: "",
            useReservedRate: true
        });

        // Sanity check: ensure that we received the rhgt number of project tokens.
        assert(beneficiaryTokenCount == projectToken.balanceOf(address(this)) - projectTokenBalanceBefore);

        // Redeem the project tokens.
        uint256 reclaimAmount = _getBackingAssets(projectToken, beneficiaryTokenCount, context.amount.token, 0);

        // Add the project tokens and the amount which was redeemed to the outbox tree for the `token`.
        // These will be bridged by the next call to `BPSucker.toRemote(...)`.
        _insertIntoTree({
            projectTokenAmount: beneficiaryTokenCount,
            token: context.amount.token,
            terminalTokenAmount: reclaimAmount,
            beneficiary: context.beneficiary
        });
    }

    /// @notice Use the default redemption behavior.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata context)
        external
        pure
        returns (uint256, uint256, uint256, JBRedeemHookSpecification[] memory)
    {
        return (context.redemptionRate, context.redeemCount, context.totalSupply, new JBRedeemHookSpecification[](0));
    }

    /// @notice A flag indicating whether an address has permission to mint a project's tokens on-demand. For this contract, this is always false.
    function hasMintPermissionFor(uint256, address) external pure returns (bool flag) {
        return false;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IJBPayHook).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
