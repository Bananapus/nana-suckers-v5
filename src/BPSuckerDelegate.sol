// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./BPSucker.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBPayHook, JBAfterPayRecordedContext} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {JBRulesetMetadataResolver} from "@bananapus/core/src/libraries/JBRulesetMetadataResolver.sol";
import {
    IJBRulesetDataHook,
    JBBeforePayRecordedContext,
    JBBeforeRedeemRecordedContext,
    JBPayHookSpecification,
    JBRedeemHookSpecification
} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

abstract contract BPSuckerDelegate is BPSucker, IJBRulesetDataHook, IJBPayHook {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    struct EncodedMetadata {
        IJBRedeemTerminal terminal;
        uint256 remoteProjectId;
        uint256 tokenAmount;
        address beneficiary;
    }

    error NOT_ALLOWED();
    error INVALID_REMOTE_PROJECT_ID(uint256 expected, uint256 received);

    /// @notice The contract storing and managing project rulesets.
    IJBRulesets public immutable RULESETS;

    /// @notice The contract that exposes price feeds.
    IJBPrices public immutable PRICES;

    constructor(IJBPrices _prices, IJBRulesets _rulesets) {
        PRICES = _prices;
        RULESETS = _rulesets;
    }

    /// @notice The data calculated before a payment is recorded in the terminal store. This data is provided to the
    /// terminal's `pay(...)` transaction.
    /// @param context The context passed to this data hook by the `pay(...)` function as a `JBBeforePayRecordedContext`
    /// struct.
    /// @return weight The new `weight` to use, overriding the ruleset's `weight`.
    /// @return hookSpecifications The amount and data to send to pay hooks instead of adding to the terminal's balance.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        if (context.projectId != PROJECT_ID) revert INVALID_REMOTE_PROJECT_ID(PROJECT_ID, context.projectId);

        address _token = context.amount.token;
        if (
            remoteMappingFor[_token]
                // Check if the token is is configured.
                .remoteToken == address(0)
            // Check if the terminal supports the redeem terminal interface.
            && !ERC165Checker.supportsInterface(address(context.terminal), type(IJBRedeemTerminal).interfaceId)
        ) {
            // In these cases we don't do anything.
            return (context.weight, new JBPayHookSpecification[](0));
        }

        // We return zero weight, so that we can do the mint on the remote chain.
        hookSpecifications = new JBPayHookSpecification[](1);
        hookSpecifications[0] = JBPayHookSpecification({hook: IJBPayHook(address(this)), amount: 0, metadata: ""});

        return (0, hookSpecifications);
    }

    function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable {
        // Check that the caller is a terminal.
        if (!DIRECTORY.isTerminalOf(context.projectId, IJBTerminal(msg.sender))) revert NOT_ALLOWED();

        // Get the projects ruleset.
        JBRuleset memory _ruleset = RULESETS.getRulesetOf(context.projectId, context.rulesetId);

        // Calculate the amount of tokens that would be minted for this payment.
        uint256 _weightRatio = context.amount.currency == _ruleset.baseCurrency()
            ? 10 ** context.amount.decimals
            : PRICES.pricePerUnitOf({
                projectId: context.projectId,
                pricingCurrency: context.amount.currency,
                unitCurrency: _ruleset.baseCurrency(),
                decimals: context.amount.decimals
            });

        uint256 _tokenCount = mulDiv(context.amount.value, context.weight, _weightRatio);

        // Get the projects token.
        IERC20 _projectToken = IERC20(address(TOKENS.tokenOf(context.projectId)));

        // Get this contract balance.
        uint256 _projectTokenBalanceBefore = _projectToken.balanceOf(address(this));

        // Mint tokens to this address.
        uint256 _beneficiaryTokenCount = IJBController(address(DIRECTORY.controllerOf(context.projectId))).mintTokensOf({
            projectId: context.projectId,
            tokenCount: _tokenCount,
            beneficiary: address(this),
            memo: "",
            useReservedRate: true
        });

        // Sanity check: we should have received the tokens.
        assert(_beneficiaryTokenCount == _projectToken.balanceOf(address(this)) - _projectTokenBalanceBefore);

        // Perform the redemption.
        uint256 _reclaimAmount = _getBackingAssets(_projectToken, _beneficiaryTokenCount, context.amount.token, 0);

        // Add the reclaim amount to the messenger queue.
        _insertIntoTree({
            projectTokenAmount: _beneficiaryTokenCount,
            redemptionToken: context.amount.token,
            redemptionTokenAmount: _reclaimAmount,
            beneficiary: context.beneficiary
        });
    }

    /// @notice We don't do anything on redemption.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata context)
        external
        pure
        returns (uint256, JBRedeemHookSpecification[] memory)
    {
        return (context.reclaimAmount.value, new JBRedeemHookSpecification[](0));
    }

    /// @notice A flag indicating whether an address has permission to mint a project's tokens on-demand.
    /// @dev A project's data hook can allow any address to mint its tokens.
    /// @param projectId The ID of the project whose token can be minted.
    /// @param addr The address to check the token minting permission of.
    /// @return flag A flag indicating whether the address has permission to mint the project's tokens on-demand.
    function hasMintPermissionFor(uint256 projectId, address addr) external pure returns (bool flag) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        // TODO: Implement
    }
}
