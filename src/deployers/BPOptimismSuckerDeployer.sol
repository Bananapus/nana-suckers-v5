// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {OPStandardBridge} from "../interfaces/OPStandardBridge.sol";
import {OPMessenger} from "../interfaces/OPMessenger.sol";
import {BPOptimismSucker, BPAddToBalanceMode} from "../BPOptimismSucker.sol";
import {IBPSucker} from "./../interfaces/IBPSucker.sol";
import {IBPSuckerDeployer} from "./../interfaces/IBPSuckerDeployer.sol";

/// @notice An `IBPSuckerDeployerFeeless` implementation to deploy `BPOptimismSucker` contracts.
contract BPOptimismSuckerDeployer is JBPermissioned, IBPSuckerDeployer {
    error ONLY_SUCKERS();
    error ALREADY_CONFIGURED();

    /// @notice The contract that exposes price feeds.
    IJBPrices immutable PRICES;

    /// @notice The contract storing and managing project rulesets.
    IJBRulesets immutable RULESETS;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable TOKENS;

    /// @notice Only this address can configure this deployer, can only be used once.
    address immutable LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The messenger used to send messages between the local and remote sucker.
    OPMessenger public MESSENGER;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    OPStandardBridge public BRIDGE;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    constructor(
        IJBPrices prices,
        IJBRulesets rulesets,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address _configurator
    ) JBPermissioned(permissions) {
        LAYER_SPECIFIC_CONFIGURATOR = _configurator;
        PRICES = prices;
        RULESETS = rulesets;
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
                    PRICES, RULESETS, DIRECTORY, TOKENS, PERMISSIONS, address(0), localProjectId, BPAddToBalanceMode.MANUAL
                )
            )
        );
        isSucker[address(sucker)] = true;
    }

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function configureLayerSpecific(OPMessenger messenger, OPStandardBridge bridge) external {
        if (address(MESSENGER) != address(0) || address(BRIDGE) != address(0)) {
            revert ALREADY_CONFIGURED();
        }
        // Configure these layer specific properties.
        // This is done in a seperate call to make the deployment code chain agnostic.
        MESSENGER = messenger;
        BRIDGE = bridge;
    }
}
