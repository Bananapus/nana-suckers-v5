// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";

import {JBBaseSucker} from "../JBBaseSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "../interfaces/IJBSuckerDeployer.sol";
import {IJBOpSuckerDeployer} from "../interfaces/IJBOpSuckerDeployer.sol";
import {IOPMessenger} from "../interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "../interfaces/IOPStandardBridge.sol";

contract JBBaseSuckerDeployer is JBPermissioned, IJBSuckerDeployer, IJBOpSuckerDeployer {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBBaseSuckerDeployer_OnlySuckers();
    error JBBaseSuckerDeployer_AlreadyConfigured();
    error JBBaseSuckerDeployer_ZeroAddress();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable override LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable override TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The messenger used to send messages between the local and remote sucker.
    IOPMessenger public override opMessenger;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    IOPStandardBridge public override opBridge;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public override isSucker;

    /// @notice A temporary storage slot used by suckers to maintain deterministic deploys.
    uint256 public override tempStoreId;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory The directory of terminals and controllers for projects.
    /// @param permissions The permissions contract for the deployer.
    /// @param tokens The contract that manages token minting and burning.
    /// @param configurator The address of the configurator.
    constructor(IJBDirectory directory, IJBPermissions permissions, IJBTokens tokens, address configurator)
        JBPermissioned(permissions)
    {
        if (configurator == address(0)) revert JBBaseSuckerDeployer_ZeroAddress();
        DIRECTORY = directory;
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
        TOKENS = tokens;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    /// @param messenger the OPMesssenger on this layer.
    /// @param bridge the OPStandardBridge on this layer.
    function configureLayerSpecific(IOPMessenger messenger, IOPStandardBridge bridge) external override {
        if (address(opMessenger) != address(0) || address(opBridge) != address(0)) {
            revert JBBaseSuckerDeployer_AlreadyConfigured();
        }
        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        opMessenger = messenger;
        opBridge = bridge;
    }

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker) {
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set for a callback to this contract.
        tempStoreId = localProjectId;

        sucker = IJBSucker(
            address(
                new JBBaseSucker{salt: salt}({
                    directory: DIRECTORY,
                    permissions: PERMISSIONS,
                    tokens: TOKENS,
                    peer: address(0),
                    addToBalanceMode: JBAddToBalanceMode.MANUAL
                })
            )
        );

        // TODO: See if resetting this value is cheaper than deletion
        // Delete after callback should complete.
        /* delete TEMP_ID_STORE; */

        isSucker[address(sucker)] = true;
    }
}
