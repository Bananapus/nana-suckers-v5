// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IBPSucker} from "../src/interfaces/IBPSucker.sol";
import {IBPSuckerDeployer} from "../src/interfaces/IBPSuckerDeployer.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BPTokenMapping} from "../src/structs/BPTokenMapping.sol";
import {BPRemoteToken} from "../src/structs/BPRemoteToken.sol";
import {BPOutboxTree} from "../src/structs/BPOutboxTree.sol";
import {BPInboxTreeRoot} from "../src/structs/BPInboxTreeRoot.sol";
import {BPMessageRoot} from "../src/structs/BPMessageRoot.sol";
import {BPClaim} from "../src/structs/BPClaim.sol";
import {BPAddToBalanceMode} from "../src/enums/BPAddToBalanceMode.sol";
import {MerkleLib} from "../src/utils/MerkleLib.sol";

import "forge-std/Test.sol";
import {BPCCIPSucker} from "../src/BPCCIPSucker.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CCIPSuckerFork is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    BPCCIPSucker public suckerOne;
    BPCCIPSucker public suckerTwo;
    BurnMintERC677Helper public ccipBnM;
    IERC20 public linkToken;
    address alice = makeAddr("alice");
    address sender = makeAddr("rootSender");
    bytes32 SALT = "SUCKER";

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    function setUp() public {

        IJBDirectory directory = IJBDirectory(makeAddr("dir"));
        IJBTokens tokens = IJBTokens(makeAddr("tokens"));
        IJBPermissions permissions = IJBPermissions(makeAddr("permissions"));
        address peer = address(0);
        BPAddToBalanceMode atbMode = BPAddToBalanceMode.MANUAL;

        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("RPC_ETHEREUM_SEPOLIA");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("RPC_ARBITRUM_SEPOLIA");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);

        suckerOne = new BPCCIPSucker{salt: SALT}(directory, tokens, permissions, peer, atbMode);

        arbSepoliaFork = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL);

        suckerTwo = new BPCCIPSucker{salt: SALT}(directory, tokens, permissions, peer, atbMode);

        vm.selectFork(sepoliaFork);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails memory sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ccipBnM = BurnMintERC677Helper(sepoliaNetworkDetails.ccipBnMAddress);
    }

    function test_forkTokenTransfer() external {
        uint256 amountToSend = 100;
        ccipBnM.drip(address(suckerOne));

        uint64 arbSepoliaChainSelector = 3478487238524512106;
        uint64 ethSepoliaChainSelector = 16015286601757825753;

        uint256 balanceBefore = ccipBnM.balanceOf(address(suckerOne));

        suckerOne.testInsertIntoTree(1e18, address(ccipBnM), amountToSend, address(suckerTwo), arbSepoliaChainSelector);

        vm.deal(sender, 1 ether);
        suckerOne.toRemote{value: 1 ether}(address(ccipBnM), arbSepoliaChainSelector);

        uint256 balanceAfer = ccipBnM.balanceOf(address(suckerOne));
        assertEq(balanceAfer, balanceBefore - amountToSend);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        Register.NetworkDetails memory arbSepoliaNetworkDetails =
            ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        BurnMintERC677Helper ccipBnMArbSepolia = BurnMintERC677Helper(arbSepoliaNetworkDetails.ccipBnMAddress);

        assertEq(ccipBnMArbSepolia.balanceOf(address(suckerOne)), amountToSend);

        // Inbox address is zero because tokens aren't mapped- this is the most simple verification that messages are being sent and received though!
        BPInboxTreeRoot memory updatedInbox = suckerTwo.getInbox(address(0), ethSepoliaChainSelector);
        assertEq(updatedInbox.root, bytes32(0));
    }

}