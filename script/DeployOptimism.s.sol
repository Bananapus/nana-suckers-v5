// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {OPStandardBridge} from "../src/interfaces/OPStandardBridge.sol";
import {OPMessenger} from "../src/interfaces/OPMessenger.sol";
import "../src/deployers/BPOptimismSuckerDeployer.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DeployOptimism is Script {
    OPMessenger CHAIN_A_OP_MESSENGER;
    string CHAIN_A_DEPLOYMENT_JSON;
    OPStandardBridge CHAIN_A_OP_BRIDGE;

    OPMessenger CHAIN_B_OP_MESSENGER;
    OPStandardBridge CHAIN_B_OP_BRIDGE;
    string CHAIN_B_DEPLOYMENT_JSON;

    function setUp() public {
        string memory CHAIN_A_RPC = vm.envString("CHAIN_A_RPC");
        string memory CHAIN_B_RPC = vm.envString("CHAIN_B_RPC");

        if (bytes(CHAIN_A_RPC).length == 0) {
            revert("CHAIN_A_RPC not set.");
        }

        if (bytes(CHAIN_B_RPC).length == 0) {
            revert("CHAIN_B_RPC not set.");
        }

        // Get chain A its chainId
        vm.createSelectFork(vm.envString("CHAIN_A_RPC"));
        uint256 _chainAId = block.chainid;
        uint256 _chainANonce = vm.getNonce(msg.sender);
        CHAIN_A_DEPLOYMENT_JSON = string.concat(
            "node_modules/@bananapus/core/broadcast/Deploy.s.sol/", Strings.toString(_chainAId), "/run-latest.json"
        );

        vm.createSelectFork(vm.envString("CHAIN_B_RPC"));
        uint256 _chainBId = block.chainid;
        uint256 _chainBNonce = vm.getNonce(msg.sender);
        CHAIN_B_DEPLOYMENT_JSON = string.concat(
            "node_modules/@bananapus/core/broadcast/Deploy.s.sol/", Strings.toString(_chainBId), "/run-latest.json"
        );

        if (_chainANonce != _chainBNonce) {
            revert("WARNING: Nonces do not match between chains.");
        }

        bool _reverse;
        if ((_chainAId == 1 && _chainBId == 10) || (_chainAId == 10 && _chainBId == 1)) {
            CHAIN_A_OP_MESSENGER = OPMessenger(address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1));
            CHAIN_A_OP_BRIDGE = OPStandardBridge(address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1));
            CHAIN_B_OP_MESSENGER = OPMessenger(address(0x4200000000000000000000000000000000000007));
            CHAIN_B_OP_BRIDGE = OPStandardBridge(address(0x4200000000000000000000000000000000000010));

            if (_chainAId == 420) _reverse = true;
        } else if ((_chainAId == 11155111 && _chainBId == 11155420) || (_chainAId == 11155111 && _chainBId == 11155420))
        {
            CHAIN_A_OP_MESSENGER = OPMessenger(address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef));
            CHAIN_A_OP_BRIDGE = OPStandardBridge(address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1));
            CHAIN_B_OP_MESSENGER = OPMessenger(address(0x4200000000000000000000000000000000000007));
            CHAIN_B_OP_BRIDGE = OPStandardBridge(address(0x4200000000000000000000000000000000000010));

            if (_chainAId == 420) _reverse = true;
        } else {
            revert(
                string.concat(
                    "The combination of chainIds ",
                    Strings.toString(_chainAId),
                    " and ",
                    Strings.toString(_chainBId),
                    " was not configured in the optimism deployment script."
                )
            );
        }

        // Flip the order of the chains.
        if (_reverse) {
            (CHAIN_A_OP_MESSENGER, CHAIN_A_OP_BRIDGE, CHAIN_B_OP_MESSENGER, CHAIN_B_OP_BRIDGE) =
                (CHAIN_B_OP_MESSENGER, CHAIN_B_OP_BRIDGE, CHAIN_A_OP_MESSENGER, CHAIN_A_OP_BRIDGE);
        }
    }

    function run() public {
        // Deploy the suckers.
        vm.createSelectFork(vm.envString("CHAIN_A_RPC"));
        vm.startBroadcast();
        address _deployerA = address(
            new BPOptimismSuckerDeployer(
                IJBPrices(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBPrices")),
                IJBRulesets(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBRulesets")),
                CHAIN_A_OP_MESSENGER,
                CHAIN_A_OP_BRIDGE,
                IJBDirectory(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBDirectory")),
                IJBTokens(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBTokens")),
                IJBPermissions(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBPermissions"))
            )
        );
        vm.stopBroadcast();

        // vm.selectFork(CHAIN_B);
        vm.createSelectFork(vm.envString("CHAIN_B_RPC"));
        vm.startBroadcast();
        address _deployerB = address(
            new BPOptimismSuckerDeployer(
                IJBPrices(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBPrices")),
                IJBRulesets(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBRulesets")),
                CHAIN_B_OP_MESSENGER,
                CHAIN_B_OP_BRIDGE,
                IJBDirectory(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBDirectory")),
                IJBTokens(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBTokens")),
                IJBPermissions(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBPermissions"))
            )
        );
        vm.stopBroadcast();

        require(_deployerA == _deployerB, "Deployed addresses do not match.");

        console2.log("Sucker A: ", Strings.toHexString(uint160(address(_deployerA)), 20));
        console2.log("Sucker B: ", Strings.toHexString(uint160(address(_deployerB)), 20));
    }

    /**
     * @notice Get the address of a contract that was deployed by the Deploy script.
     *     @dev Reverts if the contract was not found.
     *     @param _path The path to the deployment file.
     *     @param _contractName The name of the contract to get the address of.
     *     @return The address of the contract.
     */
    function _getDeploymentAddress(string memory _path, string memory _contractName) internal view returns (address) {
        string memory _deploymentJson = vm.readFile(_path);
        uint256 _nOfTransactions = stdJson.readStringArray(_deploymentJson, ".transactions").length;

        for (uint256 i = 0; i < _nOfTransactions; i++) {
            string memory _currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
            string memory _currentContractName =
                stdJson.readString(_deploymentJson, string.concat(_currentKey, ".contractName"));

            if (keccak256(abi.encodePacked(_currentContractName)) == keccak256(abi.encodePacked(_contractName))) {
                return stdJson.readAddress(_deploymentJson, string.concat(_currentKey, ".contractAddress"));
            }
        }

        revert(
            string.concat("Could not find contract with name '", _contractName, "' in deployment file '", _path, "'")
        );
    }
}
