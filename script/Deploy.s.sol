// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../src/deployers/BPOptimismSuckerDeployer.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";
import {BPSuckerRegistry} from "./../src/BPSuckerRegistry.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the addressed of the deployers that will get pre-approved.
    address[] PRE_APPROVED_DEPLOYERS;

    function configureSphinx() public override {
        // TODO: Update to contain JB Emergency Developers
        sphinxConfig.owners = [0x26416423d530b1931A2a7a6b7D435Fac65eED27d];
        sphinxConfig.orgId = "cltepuu9u0003j58rjtbd0hvu";
        sphinxConfig.projectName = "nana-suckers";
        sphinxConfig.threshold = 1;
        sphinxConfig.mainnets = ["ethereum", "optimism"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia"];
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

        // Deploy the registry and pre-aprove the deployers we just deployed.
        new BPSuckerRegistry(core.projects, core.permissions, PRE_APPROVED_DEPLOYERS);
    }

    function _optimismSucker() internal {
        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11155111) {
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    new BPOptimismSuckerDeployer(
                        core.prices,
                        core.rulesets,
                        OPMessenger(
                            block.chainid == 1
                                ? address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1)
                                : address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef)
                        ),
                        OPStandardBridge(
                            block.chainid == 1
                                ? address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1)
                                : address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1)
                        ),
                        core.directory,
                        core.tokens,
                        core.permissions
                    )
                )
            );
        }

        // Check if we should do the L1 portion.
        // OP & OP Sepolia.
        if (block.chainid == 10 || block.chainid == 11155420) {
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    new BPOptimismSuckerDeployer(
                        core.prices,
                        core.rulesets,
                        OPMessenger(address(0x4200000000000000000000000000000000000007)),
                        OPStandardBridge(address(0x4200000000000000000000000000000000000010)),
                        core.directory,
                        core.tokens,
                        core.permissions
                    )
                )
            );
        }
    }
}
