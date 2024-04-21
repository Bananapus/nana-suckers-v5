// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../src/deployers/BPOptimismSuckerDeployer.sol";
import "../src/deployers/BPArbitrumSuckerDeployer.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";
import {BPSuckerRegistry} from "./../src/BPSuckerRegistry.sol";
import {ARBChains} from "../src/libraries/ARBChains.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the addressed of the deployers that will get pre-approved.
    address[] PRE_APPROVED_DEPLOYERS;

    /// @notice the nonces that are used to deploy the contracts.
    bytes32 OP_SALT = "SUCKER_ETH_OP";
    bytes32 ARB_SALT = "SUCKER_ETH_ARB";
    bytes32 REGISTRY_SALT = "REGISTRY";

    function configureSphinx() public override {
        // TODO: Update to contain JB Emergency Developers
        sphinxConfig.owners = [0x26416423d530b1931A2a7a6b7D435Fac65eED27d];
        sphinxConfig.orgId = "cltepuu9u0003j58rjtbd0hvu";
        sphinxConfig.projectName = "nana-suckers";
        sphinxConfig.threshold = 1;
        sphinxConfig.mainnets = ["ethereum", "optimism"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia"];
        sphinxConfig.saltNonce = 2;
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        // Perform the deployments for this chain, then deploy the registry and pre-approve the deployers.
        _optimismSucker();
        _arbitrumSucker();

        // If the registry is already deployed we don't have to deploy it
        // (and we can't add more pre_approved deployers etc.)
        if (
            !_isDeployed(
                REGISTRY_SALT,
                type(BPSuckerRegistry).creationCode,
                abi.encode(core.projects, core.permissions, safeAddress())
            )
        ) {
            // Deploy the registry and pre-aprove the deployers we just deployed.
            BPSuckerRegistry _registry =
                new BPSuckerRegistry{salt: REGISTRY_SALT}(core.projects, core.permissions, safeAddress());

            // Before transferring ownership to JBDAO we approve the deployers.
            if (PRE_APPROVED_DEPLOYERS.length != 0) {
                _registry.allowSuckerDeployers(PRE_APPROVED_DEPLOYERS);
            }

            // Transfer ownership to JBDAO.
            _registry.transferOwnershipToProject(1);
        }
    }

    /// @notice handles the deployment and configuration regarding optimism (this also includes the mainnet configuration).
    function _optimismSucker() internal {
        // Check if this sucker is already deployed on this chain,
        // if that is the case we don't need to do anything else for this chain.
        if (
            _isDeployed(
                OP_SALT,
                type(BPOptimismSuckerDeployer).creationCode,
                abi.encode(core.directory, core.tokens, core.permissions, safeAddress())
            )
        ) return;

        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11155111) {
            BPOptimismSuckerDeployer _opDeployer = new BPOptimismSuckerDeployer{salt: OP_SALT}(
                core.directory, core.tokens, core.permissions, safeAddress()
            );

            _opDeployer.configureLayerSpecific(
                OPMessenger(
                    block.chainid == 1
                        ? address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1)
                        : address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef)
                ),
                OPStandardBridge(
                    block.chainid == 1
                        ? address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1)
                        : address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1)
                )
            );

            PRE_APPROVED_DEPLOYERS.push(address(_opDeployer));
        }

        // Check if we should do the L2 portion.
        // OP & OP Sepolia.
        if (block.chainid == 10 || block.chainid == 11155420) {
            BPOptimismSuckerDeployer _opDeployer = new BPOptimismSuckerDeployer{salt: OP_SALT}(
                core.directory, core.tokens, core.permissions, safeAddress()
            );

            _opDeployer.configureLayerSpecific(
                OPMessenger(0x4200000000000000000000000000000000000007),
                OPStandardBridge(0x4200000000000000000000000000000000000010)
            );

            PRE_APPROVED_DEPLOYERS.push(address(_opDeployer));
        }
    }

    /// @notice handles the deployment and configuration regarding optimism (this also includes the mainnet configuration).
    function _arbitrumSucker() internal {
        // Check if this sucker is already deployed on this chain,
        // if that is the case we don't need to do anything else for this chain.
        if (
            _isDeployed(
                ARB_SALT,
                type(BPArbitrumSuckerDeployer).creationCode,
                abi.encode(core.directory, core.tokens, core.permissions, safeAddress())
            )
        ) return;

        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11155111) {
            BPArbitrumSuckerDeployer _arbDeployer = new BPArbitrumSuckerDeployer{salt: ARB_SALT}(
                core.directory, core.tokens, core.permissions, safeAddress()
            );

            PRE_APPROVED_DEPLOYERS.push(address(_arbDeployer));
        }

        // Check if we should do the L2 portion.
        // ARB & ARB Sepolia.
        if (block.chainid == 10 || block.chainid == 421614) {
            BPArbitrumSuckerDeployer _arbDeployer = new BPArbitrumSuckerDeployer{salt: ARB_SALT}(
                core.directory, core.tokens, core.permissions, safeAddress()
            );

            PRE_APPROVED_DEPLOYERS.push(address(_arbDeployer));
        }
    }

    function _isDeployed(bytes32 salt, bytes memory creationCode, bytes memory arguments)
        internal
        view
        returns (bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return address(_deployedTo).code.length != 0;
    }
}
