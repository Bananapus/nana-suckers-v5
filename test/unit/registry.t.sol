// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import "../../src/BPOptimismSucker.sol";
import "../../src/deployers/BPOptimismSuckerDeployer.sol";

import {BPLeaf} from "../../src/structs/BPLeaf.sol";
import {BPClaim} from "../../src/structs/BPClaim.sol";

import {JBProjects} from "@bananapus/core/src/JBProjects.sol"; 
import {JBPermissions} from "@bananapus/core/src/JBPermissions.sol"; 

import {BPSuckerRegistry} from "./../../src/BPSuckerRegistry.sol";

contract RegistryUnitTest is Test {
    function testDeployNoProjectCheck() public {
        JBProjects _projecs = new JBProjects(msg.sender, address(0));
        JBPermissions _permissions = new JBPermissions();
        new BPSuckerRegistry(_projecs, _permissions, address(100));
    }


    function testTransferWithProjectCheck() public {
        JBProjects _projecs = new JBProjects(msg.sender, address(0));
        JBPermissions _permissions = new JBPermissions();

        BPSuckerRegistry _registry = new BPSuckerRegistry(_projecs, _permissions, address(100));

        vm.expectRevert();
        vm.prank(address(100));
        _registry.transferOwnershipToProject(1);
    
    } 
}