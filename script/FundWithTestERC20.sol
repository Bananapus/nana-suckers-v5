// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    BPOptimismSucker,
    IJBDirectory,
    IJBTokens,
    IJBPermissions,
    BPTokenMapConfig,
    OPStandardBridge
} from "../src/BPOptimismSucker.sol";

interface OPTestBridgeToken is IERC20 {
    function faucet() external;
}

contract FundWithTestERC20 is Script {
    string CHAIN_A_RPC;
    string CHAIN_B_RPC;

    OPStandardBridge constant CHAIN_A_OP_BRIDGE = OPStandardBridge(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1);

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
        uint256 _chainA = vm.createSelectFork(CHAIN_A_RPC);

        OPTestBridgeToken _testToken = OPTestBridgeToken(0x12608ff9dac79d8443F17A4d39D93317BAD026Aa);
        uint256 _amount = 1000_000_000_000_000_000_000;

        vm.startBroadcast();

        // Use the faucet
        _testToken.faucet();

        // Approve the tokens to be bridged
        _testToken.approve(address(CHAIN_A_OP_BRIDGE), _amount);

        // Perform the bridge.
        CHAIN_A_OP_BRIDGE.bridgeERC20To({
            localToken: address(_testToken),
            remoteToken: address(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2),
            to: address(msg.sender),
            amount: _amount,
            minGasLimit: 200_000,
            extraData: bytes("")
        });
    }
}
