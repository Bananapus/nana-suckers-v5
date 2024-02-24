// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBPSuckerDeployer} from "../interfaces/IBPSuckerDeployer.sol";
import {BPTokenMapping} from "./BPTokenMapping.sol";

struct BPSuckerDeployerConfig {
    IBPSuckerDeployer deployer;
    BPTokenMapping[] mappings;
}
