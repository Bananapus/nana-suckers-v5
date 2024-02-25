// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPayoutTerminal.sol";

import {OPStandardBridge} from "../interfaces/OPStandardBridge.sol";
import {OPMessenger} from "../interfaces/OPMessenger.sol";
import {BPOptimismSucker} from "../BPOptimismSucker.sol";
import {IBPSucker} from "./../interfaces/IBPSucker.sol";
import {IBPSuckerDeployerFeeless} from "./../interfaces/IBPSuckerDeployerFeeless.sol";

/// @notice An `IBPSuckerDeployerFeeless` implementation to deploy `BPOptimismSucker` contracts.
contract BPOptimismSuckerDeployer is JBPermissioned, IBPSuckerDeployerFeeless {
    error ONLY_SUCKERS();

    /// @notice The contract that exposes price feeds.
    IJBPrices immutable PRICES;

    /// @notice The contract storing and managing project rulesets.
    IJBRulesets immutable RULESETS;

    /// @notice The messenger used to send messages between the local and remote sucker.
    OPMessenger immutable MESSENGER;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    OPStandardBridge immutable BRIDGE;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable TOKENS;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    constructor(
        IJBPrices prices,
        IJBRulesets rulesets,
        OPMessenger messenger,
        OPStandardBridge bridge,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions
    ) JBPermissioned(permissions) {
        PRICES = prices;
        RULESETS = rulesets;
        MESSENGER = messenger;
        BRIDGE = bridge;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    /// @notice Create a new `BPSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IBPSucker sucker) {
        salt = keccak256(abi.encodePacked(msg.sender, salt));
        sucker = IBPSucker(
            address(
                new BPOptimismSucker{salt: salt}(
                    PRICES, RULESETS, MESSENGER, BRIDGE, DIRECTORY, TOKENS, PERMISSIONS, address(0), localProjectId
                )
            )
        );
        isSucker[address(sucker)] = true;
    }

    /// @notice Use a project's surplus allowance without paying exit fees.
    /// @dev This function can only be called by suckers deployed by this contract.
    /// @dev This function can only be called by suckers with `JBPermissionIds.USE_ALLOWANCE` permission from the project's owner.
    /// @dev This function is not necessarily feeless, as it still requires JuiceboxDAO to set the address as feeless.
    /// @param projectId The project's ID.
    /// @param terminal The terminal to use the surplus allowance from.
    /// @param token The token that the surplus is in.
    /// @param currency The currency that the `amount` is denominated in.
    /// @param amount The amount to use from the terminal, denominated in the `currency`.
    /// @param minReceivedTokens The minimum amount of terminal tokens to receive. If the terminal returns less than this amount, the transaction will revert.
    /// @return The amount of tokens received.
    function useAllowanceFeeless(
        uint256 projectId,
        IJBPayoutTerminal terminal,
        address token,
        uint32 currency,
        uint256 amount,
        uint256 minReceivedTokens
    ) external returns (uint256) {
        // Make sure the caller is a sucker.
        if (!isSucker[msg.sender]) {
            revert ONLY_SUCKERS();
        }

        // Access control: only suckers with `JBPermissionIds.USE_ALLOWANCE` permission from the project's owner can use the allowance.
        _requirePermissionFrom(DIRECTORY.PROJECTS().ownerOf(projectId), projectId, JBPermissionIds.USE_ALLOWANCE);

        // Use the allowance.
        return terminal.useAllowanceOf(
            projectId, token, amount, currency, minReceivedTokens, payable(address(msg.sender)), string("")
        );
    }
}
