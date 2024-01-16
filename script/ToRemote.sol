// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {BPOptimismSucker, IJBDirectory, IJBTokens, IJBPermissions} from "../src/BPOptimismSucker.sol";
import {BPSuckerDelegate} from "../src/BPSuckerDelegate.sol";
import {OPMessenger} from "../src/interfaces/OPMessenger.sol";

import {Strings} from "../lib/juice-contracts-v4/lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IJBPermissions, JBPermissionsData} from "juice-contracts-v4/src/interfaces/IJBPermissions.sol";
import "juice-contracts-v4/src/libraries/JBPermissionIds.sol";
// import "../lib/juice-contracts-v4/src/interfaces/IJBController.sol";
// import "../lib/juice-contracts-v4/src/interfaces/terminal/IJBRedeemTerminal.sol";
import "juice-contracts-v4/src/interfaces/terminal/IJBMultiTerminal.sol";
// import "juice-contracts-v4/src/interfaces/IJBPriceFeed.sol"; 
// import "../lib/juice-contracts-v4/src/interfaces/IJBPrices.sol"; 
import "../lib/juice-contracts-v4/src/libraries/JBConstants.sol";
// import "juice-contracts-v4/src/libraries/JBPermissionIds.sol";
// import {JBRulesetConfig} from "juice-contracts-v4/src/structs/JBRulesetConfig.sol";
// import {JBFundAccessLimitGroup} from "../lib/juice-contracts-v4/src/structs/JBFundAccessLimitGroup.sol";
// import {IJBRulesetApprovalHook} from "juice-contracts-v4/src/interfaces/IJBRulesetApprovalHook.sol";
// import {IJBPermissions, JBPermissionsData} from "juice-contracts-v4/src/interfaces/IJBPermissions.sol";

contract PermissionsScript is Script {
    // Sepolia config
    string CHAIN_A_RPC;
    OPMessenger constant CHAIN_A_OP_MESSENGER = OPMessenger(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef);
    string CHAIN_A_DEPLOYMENT_JSON = "lib/juice-contracts-v4/broadcast/Deploy.s.sol/11155111/run-latest.json";
    uint256 PROJECT_ID_CHAIN_A = 2;

    // OP Sepolia config
    string CHAIN_B_RPC;
    OPMessenger constant CHAIN_B_OP_MESSENGER = OPMessenger(0x4200000000000000000000000000000000000007);
    string CHAIN_B_DEPLOYMENT_JSON = "lib/juice-contracts-v4/broadcast/Deploy.s.sol/11155420/run-latest.json";
    uint256 PROJECT_ID_CHAIN_B = 1;

    function setUp() public {
        CHAIN_A_RPC = vm.envString("CHAIN_A_RPC");
        CHAIN_B_RPC = vm.envString("CHAIN_B_RPC");

        if (bytes(CHAIN_A_RPC).length == 0) {
            revert("CHAIN_A_RPC not set.");
        }

        if (bytes(CHAIN_B_RPC).length == 0) {
            revert("CHAIN_B_RPC not set.");
        }
    }

    function run() public {
        // Get the nonces for the two chains.
        vm.createSelectFork(CHAIN_B_RPC);

        vm.startBroadcast();
        IJBMultiTerminal(0x274DaF03AE4025Efb01A051ab0385D0AA77ceb26).pay{value: 50_000}({
            projectId: PROJECT_ID_CHAIN_B,
            token: JBConstants.NATIVE_TOKEN,
            amount: 50_000,
            beneficiary: msg.sender,
            minReturnedTokens: 0,
            memo: "",
            metadata: bytes("")
        });

        address[] memory _beneficiaries = new address[](1);
        _beneficiaries[0] = msg.sender;

        BPSuckerDelegate(payable(0xb2DBff7BAC73E4bA21f134593F9a8eC46063D419)).toRemote(
            JBConstants.NATIVE_TOKEN,
            _beneficiaries
        );



        // 0x274daf03ae4025efb01a051ab0385d0aa77ceb26
        // Chain A: 0xa3cedc2a2bda2487132273d4ee1107dad81b6ef9
        // Chain B: 0xb2dbff7bac73e4ba21f134593f9a8ec46063d419 
        // console2.log("the address: ", Strings.toHexString(uint160(address(_address)), 20));
        // uint256[] memory _permissions = new uint256[](1);
        // _permissions[0] = JBPermissionIds.MINT_TOKENS;

        // vm.broadcast();
        // _permissionStore.setPermissionsFor(
        //     address(msg.sender),
        //     JBPermissionsData({operator: address(0xb2DBff7BAC73E4bA21f134593F9a8eC46063D419), projectId: PROJECT_ID_CHAIN_B, permissionIds: _permissions})
        // );

        // console2.log("Chain B projectID", Strings.toString(_projectIdB));
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