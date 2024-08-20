// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";

import {JBArbitrumSucker} from "../JBArbitrumSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {JBLayer} from "../enums/JBLayer.sol";
import {IArbGatewayRouter} from "../interfaces/IArbGatewayRouter.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";
import {ARBAddresses} from "../libraries/ARBAddresses.sol";
import {ARBChains} from "../libraries/ARBChains.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBArbitrumSuckerDeployer is JBPermissioned, IJBSuckerDeployer {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBArbitrumSuckerDeployer_OnlySuckers();
    error JBArbitrumSuckerDeployer_AlreadyConfigured();
    error JBArbitrumSuckerDeployer_ZeroAddress();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable override DIRECTORY;

    /// @notice The layer that this contract is on.
    JBLayer public immutable override LAYER;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable override LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable override TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public override isSucker;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice A temporary storage slot used by suckers to maintain deterministic deploys.
    uint256 internal _tempIdStore;

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
        if (configurator == address(0)) revert JBArbitrumSuckerDeployer_ZeroAddress();
        DIRECTORY = directory;
        TOKENS = tokens;
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the gateway router address for the current chain
    /// @return gateway for the current chain.
    function gatewayRouter() external view returns (IArbGatewayRouter gateway) {
        uint256 chainId = block.chainid;
        if (chainId == ARBChains.ETH_CHAINID) return IArbGatewayRouter(ARBAddresses.L1_GATEWAY_ROUTER);
        if (chainId == ARBChains.ARB_CHAINID) return IArbGatewayRouter(ARBAddresses.L2_GATEWAY_ROUTER);
        if (chainId == ARBChains.ETH_SEP_CHAINID) return IArbGatewayRouter(ARBAddresses.L1_SEP_GATEWAY_ROUTER);
        if (chainId == ARBChains.ARB_SEP_CHAINID) return IArbGatewayRouter(ARBAddresses.L2_SEP_GATEWAY_ROUTER);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external override returns (IJBSucker sucker) {
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set for a callback to this contract.
        _tempIdStore = localProjectId;

        sucker = IJBSucker(
            address(
                new JBArbitrumSucker{salt: salt}(DIRECTORY, PERMISSIONS, TOKENS, address(0), JBAddToBalanceMode.MANUAL)
            )
        );

        // TODO: See if resetting this value is cheaper than deletion
        // Delete after callback should complete.
        /* delete TEMP_ID_STORE; */

        isSucker[address(sucker)] = true;
    }


    /* /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function configureLayerSpecific(OPMessenger messenger, OPStandardBridge bridge) external {
        if (address(MESSENGER) != address(0) || address(BRIDGE) != address(0)) {
            revert ALREADY_CONFIGURED();
        }
        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        MESSENGER = messenger;
        BRIDGE = INBOX.bridge();
    } */
}
