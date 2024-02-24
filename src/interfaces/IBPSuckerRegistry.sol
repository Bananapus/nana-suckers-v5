// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IBPSuckerDeployer} from "./IBPSuckerDeployer.sol";
import {BPTokenMapping} from "../structs/BPTokenMapping.sol";

struct SuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenMapping[] tokenConfigurations;
}

interface IBPSuckerRegistry {
    function isSuckerOf(uint256 projectId, address suckerAddress) external view returns (bool);
    function suckersOf(uint256 projectId) external view returns (address[] memory);
    function suckerDeployerIsAllowed(address deployer) external view returns (bool);

    function allowSuckerDeployer(address deployer) external;
    function deploySuckersFor(uint256 projectId, bytes32 salt, SuckerDeployerConfig[] memory configurations)
        external
        returns (address[] memory suckers);
}
