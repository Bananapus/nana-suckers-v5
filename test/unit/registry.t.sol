// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IJBController} from "@bananapus/core-v5/src/interfaces/IJBController.sol";
import "../../src/JBOptimismSucker.sol";
import "../../src/deployers/JBOptimismSuckerDeployer.sol";

import {JBLeaf} from "../../src/structs/JBLeaf.sol";
import {JBClaim} from "../../src/structs/JBClaim.sol";

import {JBProjects} from "@bananapus/core-v5/src/JBProjects.sol";
import {JBDirectory} from "@bananapus/core-v5/src/JBDirectory.sol";
import {JBPermissions} from "@bananapus/core-v5/src/JBPermissions.sol";

import {JBSuckerRegistry} from "./../../src/JBSuckerRegistry.sol";

contract RegistryUnitTest is Test {
    function testDeployNoProjectCheck() public {
        JBProjects _projects = new JBProjects(msg.sender, address(0));
        JBPermissions _permissions = new JBPermissions();
        JBDirectory _directory = new JBDirectory(_permissions, _projects, address(100));
        new JBSuckerRegistry(_directory, _permissions, address(100), address(0));
    }
}
