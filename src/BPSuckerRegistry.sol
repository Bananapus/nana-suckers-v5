// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBPSuckerRegistry, SuckerDeployerConfig, IBPSucker, BPTokenConfig} from "./interfaces/IBPSuckerRegistry.sol";
import {JBOwnable, IJBProjects, IJBPermissions} from "@bananapus/ownable/src/JBOwnable.sol";

contract BPSuckerRegistry is JBOwnable, IBPSuckerRegistry {

    error INVALID_DEPLOYER(address _deployer);

    // TODO: Replace with correct permission id.
    uint8 constant DEPLOY_SUCKERS_PERMISSION_ID = 100;

    mapping(uint256 projectId => IBPSucker[]) internal _suckersOf;

    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    constructor(
        IJBProjects _projects,
        IJBPermissions _permissions
    ) JBOwnable(_projects, _permissions) {
        // Transfer ownership to projectID 1 owner (JBDAO).
        _transferOwnership(address(0), uint88(1));
    }

    function suckersOf(uint256 projectId) external view returns (IBPSucker[] memory) {
        return _suckersOf[projectId];
    }

    function allowSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = true;
    }

    function deploySuckersFor(
        uint256 projectId,
        bytes32 salt,
        SuckerDeployerConfig[] calldata configurations
    )
        public
        override
    {
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: DEPLOY_SUCKERS_PERMISSION_ID
        });

        // This makes it so the sender has to be the same for both chains in order to link projects.
        salt = keccak256(abi.encode(msg.sender, salt));

        // Keep a reference to the number of sucker deployers.
        uint256 numberOfSuckerDeployers = configurations.length;

        // Keep a reference to the sucker deploy being iterated on.
        SuckerDeployerConfig memory configuration;

        for (uint256 i; i < numberOfSuckerDeployers; i++) {
            // Get the configuration being iterated on.
            configuration = configurations[i];

            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configuration.deployer)])
                revert INVALID_DEPLOYER(address(configuration.deployer));

            // Create the sucker.
            IBPSucker sucker = configuration.deployer.createForSender({_localProjectId: projectId, _salt: salt});

            // Keep a reference to the number of token configurations for the sucker.
            uint256 numberOfTokenConfigurations = configuration.tokenConfigurations.length;

            // Keep a reference to the token configurations being iterated on.
            BPTokenConfig memory tokenConfiguration;

            // Configure the tokens for the sucker.
            for (uint256 j; j < numberOfTokenConfigurations; j++) {
                // Get a reference to the configuration being iterated on.
                tokenConfiguration = configuration.tokenConfigurations[j];

                // Configure the sucker.
                sucker.configureToken(
                    BPTokenConfig({
                        localToken: tokenConfiguration.localToken,
                        remoteToken: tokenConfiguration.remoteToken,
                        minGas: tokenConfiguration.minGas,
                        minBridgeAmount: tokenConfiguration.minBridgeAmount
                    })
                );
            }
        }
    }
}