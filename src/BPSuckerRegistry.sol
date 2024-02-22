// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBPSuckerRegistry, SuckerDeployerConfig, IBPSucker, BPTokenConfig} from "./interfaces/IBPSuckerRegistry.sol";

contract BPSuckerRegistry is IBPSuckerRegistry {
    mapping(uint256 projectId => IBPSucker[]) internal _suckersOf;

    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    function suckersOf(uint256 projectId) external view returns (IBPSucker[] memory) {
        return _suckersOf[projectId];
    }

    function allowSuckerDeployer(address deployer) public override {
        // TODO onlyOwner // jbdao.
        suckerDeployerIsAllowed[deployer] = true;
    }

    function deploySuckersFor(
        uint256 projectId,
        bytes32 salt,
        SuckerDeployerConfig[] memory configurations
    )
        public
        override
    {
        // TODO requirePermissions from owner of projectId or Operator of a new DEPLOY_SUCKERS permission.

        // Keep a reference to the number of sucker deployers.
        uint256 numberOfSuckerDeployers = configurations.length;

        // Keep a reference to the sucker deploy being iterated on.
        SuckerDeployerConfig memory configuration;

        for (uint256 i; i < numberOfSuckerDeployers; i++) {
            // Get the configuration being iterated on.
            configuration = configurations[i];

            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configuration.deployer)]) revert();

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