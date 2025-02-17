// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./helpers/SuckerDeploymentLib.sol";
import "../src/deployers/JBOptimismSuckerDeployer.sol";
import "../src/deployers/JBBaseSuckerDeployer.sol";
import "../src/deployers/JBArbitrumSuckerDeployer.sol";
import "../src/deployers/JBCCIPSuckerDeployer.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";
import {JBSuckerRegistry} from "./../src/JBSuckerRegistry.sol";
import {ICCIPRouter} from "./../src/interfaces/ICCIPRouter.sol";
import {ARBAddresses} from "../src/libraries/ARBAddresses.sol";
import {ARBChains} from "../src/libraries/ARBChains.sol";
import {CCIPHelper} from "../src/libraries/CCIPHelper.sol";

contract FixArbDeployer is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the sucker contracts for the chain we are deploying to.
    SuckerDeployment suckers;
    /// @notice tracks the addressed of the deployers that will get pre-approved.
    address[] PRE_APPROVED_DEPLOYERS;

    address TRUSTED_FORWARDER;

    /// @notice the nonces that are used to deploy the contracts.
    bytes32 ARB_SALT = "_SUCKER_ETH_ARB_";

    address ARB_SUCKER_DEPLOYER = address(0x5021c398D556925315C73A8f559d98117723967a);

    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-suckers";
        sphinxConfig.mainnets = ["arbitrum", "optimism"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );

        // Get the deployment addresses for the suckers contracts for this chain.
        suckers = SuckerDeploymentLib.getDeployment(vm.envOr("NANA_SUCKERS_DEPLOYMENT_PATH", string("./deployments/")));

        // We use the same trusted forwarder as the core deployment.
        TRUSTED_FORWARDER = core.controller.trustedForwarder();

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        if (block.chainid == 10) {
            _removeArbSuckerOnOptimism();
        }

        if (block.chainid == 42_161) {
            _deployArbSucker();
        }
    }

    function _removeArbSuckerOnOptimism() internal {
        suckers.registry.removeSuckerDeployer(ARB_SUCKER_DEPLOYER);
    }

    function _deployArbSucker() internal {
        JBArbitrumSuckerDeployer _arbDeployer = new JBArbitrumSuckerDeployer{salt: ARB_SALT}({
            directory: core.directory,
            permissions: core.permissions,
            tokens: core.tokens,
            configurator: safeAddress(),
            trusted_forwarder: TRUSTED_FORWARDER
        });

        require(address(_arbDeployer) == ARB_SUCKER_DEPLOYER, "ARB sucker did not compile correctly.");

        _arbDeployer.setChainSpecificConstants({
            layer: JBLayer.L2,
            inbox: IInbox(address(0)),
            gatewayRouter: IArbGatewayRouter(
                block.chainid == 42_161 ? ARBAddresses.L2_GATEWAY_ROUTER : ARBAddresses.L2_SEP_GATEWAY_ROUTER
            )
        });

        // Deploy the singleton instance.
        JBArbitrumSucker _singleton = new JBArbitrumSucker{salt: ARB_SALT}({
            deployer: _arbDeployer,
            directory: core.directory,
            permissions: core.permissions,
            tokens: core.tokens,
            addToBalanceMode: JBAddToBalanceMode.MANUAL,
            trusted_forwarder: TRUSTED_FORWARDER
        });

        // Configure the deployer to use the singleton instance.
        _arbDeployer.configureSingleton(_singleton);

        // Approve it on the registry.
        suckers.registry.allowSuckerDeployer(address(_arbDeployer));
    }
}
