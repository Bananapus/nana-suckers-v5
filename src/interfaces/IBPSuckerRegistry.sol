// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IBPSucker} from "./IBPSucker.sol";
import {IBPSuckerDeployer} from "./IBPSuckerDeployer.sol";
import {BPTokenConfig} from "./../structs/BPTokenConfig.sol";

struct SuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenConfig[] tokenConfigurations;
}

interface IBPSuckerRegistry {
    function suckersOf(uint256 projectId) external view returns (IBPSucker[] memory);
    function suckerDeployerIsAllowed(address deployer) external view returns (bool);

    function allowSuckerDeployer(address deployer) external;
    function deploySuckersFor(
        uint256 projectId,
        bytes32 salt,
        SuckerDeployerConfig[] memory configurations
    )
        external;
}