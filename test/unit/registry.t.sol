// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import "../../src/JBOptimismSucker.sol";
import "../../src/deployers/JBOptimismSuckerDeployer.sol";

import {JBLeaf} from "../../src/structs/JBLeaf.sol";
import {JBClaim} from "../../src/structs/JBClaim.sol";

import {JBProjects} from "@bananapus/core/src/JBProjects.sol";
import {JBPermissions} from "@bananapus/core/src/JBPermissions.sol";

import {JBSuckerRegistry} from "./../../src/JBSuckerRegistry.sol";

contract RegistryUnitTest is Test {
    function testDeployNoProjectCheck() public {
        JBProjects _projecs = new JBProjects(msg.sender, address(0));
        JBPermissions _permissions = new JBPermissions();
        new JBSuckerRegistry(_projecs, _permissions, address(100));
    }

    function testTransferWithProjectCheck() public {
        JBProjects _projecs = new JBProjects(msg.sender, address(0));
        JBPermissions _permissions = new JBPermissions();

        JBSuckerRegistry _registry = new JBSuckerRegistry(_projecs, _permissions, address(100));

        vm.expectRevert();
        vm.prank(address(100));
        _registry.transferOwnershipToProject(1);
    }
}
