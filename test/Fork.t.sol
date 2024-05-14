// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from "@bananapus/core/test/mock/MockPriceFeed.sol";
import {IBPSucker} from "../src/interfaces/IBPSucker.sol";
import {IBPSuckerDeployer} from "../src/interfaces/IBPSuckerDeployer.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
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

contract CCIPSuckerFork is TestBaseWorkflow {
    uint8 private constant _WEIGHT_DECIMALS = 18; // FIXED
    uint8 private constant _NATIVE_DECIMALS = 18; // FIXED
    uint256 private constant _TEST_PRICE_PER_NATIVE = 100 * 10 ** 18; // 2000 test token == 1 native token
    uint256 private _weight = 1000 * 10 ** _WEIGHT_DECIMALS;

    JBRulesetMetadata private _metadata;

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

    IJBToken projectOneToken;

    function setUp() public override {

        address peer = address(0);
        BPAddToBalanceMode atbMode = BPAddToBalanceMode.MANUAL;

        uint64 arbSepoliaChainSelector = 3478487238524512106;
        uint64 ethSepoliaChainSelector = 16015286601757825753;

        uint64[] memory allowedChains = new uint64[](2);
        allowedChains[0] = arbSepoliaChainSelector;
        allowedChains[1] = ethSepoliaChainSelector;

        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("RPC_ETHEREUM_SEPOLIA");
        string memory ARBITRUM_SEPOLIA_RPC_URL = vm.envString("RPC_ARBITRUM_SEPOLIA");
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        Register.NetworkDetails memory sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ccipBnM = BurnMintERC677Helper(sepoliaNetworkDetails.ccipBnMAddress);
        vm.makePersistent(address(ccipBnM));

        _metadata = JBRulesetMetadata({
            reservedRate: JBConstants.MAX_RESERVED_RATE / 2, //50%
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE, //50%
            baseCurrency: uint32(uint160(address(JBConstants.NATIVE_TOKEN))),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalSurplusForRedemptions: true,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });

        super.setUp();

        suckerOne = new BPCCIPSucker{salt: SALT}(jbDirectory(), jbTokens(), jbPermissions(), peer, atbMode);

        // set permissions
        vm.startPrank(multisig());

        uint256[] memory ids = new uint256[](1);
        ids[0] = 9;

        // permissions to set
        JBPermissionsData memory perms = JBPermissionsData({
            operator: address(suckerOne),
            projectId: 1,
            permissionIds: ids
        });

        jbPermissions().setPermissionsFor(multisig(), perms);

        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: 10 * 10 ** _NATIVE_DECIMALS,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: 5 * 10 ** _NATIVE_DECIMALS,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(jbMultiTerminal()),
                token: JBConstants.NATIVE_TOKEN,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });
        }

        {
            // Package up the ruleset configuration.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].duration = 0;
            _rulesetConfigurations[0].weight = _weight;
            _rulesetConfigurations[0].decayRate = 0;
            _rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroups = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            address[] memory _tokensToAccept = new address[](2);
            _tokensToAccept[0] = JBConstants.NATIVE_TOKEN;
            _tokensToAccept[1] = address(ccipBnM);
            _terminalConfigurations[0] = JBTerminalConfig({terminal: jbMultiTerminal(), tokensToAccept: _tokensToAccept});

            // Create a first project to collect fees.
            jbController().launchProjectFor({
                owner: multisig(), // Random.
                projectUri: "whatever",
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
                memo: ""
            });

            projectOneToken = jbController().deployERC20For(1, "SuckerToken", "SOOK", bytes32(0));

            MockPriceFeed _priceFeedNativeUsd = new MockPriceFeed(_TEST_PRICE_PER_NATIVE, 18);
            vm.label(address(_priceFeedNativeUsd), "Mock Price Feed Native-ccipBnM");

            IJBPrices(jbPrices()).addPriceFeedFor({
                projectId: 1,
                pricingCurrency: uint32(uint160(address(ccipBnM))),
                unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                priceFeed: IJBPriceFeed(_priceFeedNativeUsd)
            });

        }

        suckerOne.setAllowedChains(allowedChains);

        vm.stopPrank();

        arbSepoliaFork = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL);

        super.setUp();

        /* suckerTwo = new BPCCIPSucker{salt: SALT}(jbDirectory(), jbTokens(), jbPermissions(), peer, atbMode); */
        deployCodeTo("BPCCIPSucker.sol", abi.encode(jbDirectory(), jbTokens(), jbPermissions(), peer, atbMode), address(suckerOne));

        // set permissions
        vm.startPrank(multisig());

        {
            // Package up the ruleset configuration.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].duration = 0;
            _rulesetConfigurations[0].weight = _weight;
            _rulesetConfigurations[0].decayRate = 0;
            _rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroups = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            address[] memory _tokensToAccept = new address[](2);
            _tokensToAccept[0] = JBConstants.NATIVE_TOKEN;
            _tokensToAccept[1] = address(ccipBnM);
            _terminalConfigurations[0] = JBTerminalConfig({terminal: jbMultiTerminal(), tokensToAccept: _tokensToAccept});

            // Create a first project to collect fees.
            jbController().launchProjectFor({
                owner: multisig(), // Random.
                projectUri: "whatever",
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
                memo: ""
            });
        }

        jbPermissions().setPermissionsFor(multisig(), perms);

        suckerOne.setAllowedChains(allowedChains);

        vm.stopPrank();

        vm.makePersistent(address(ccipBnM));

        vm.selectFork(sepoliaFork);
    }

    function test_forkTokenTransfer() external {
        address user = makeAddr("him");
        uint256 amountToSend = 100;
        ccipBnM.drip(address(user));

        uint64 arbSepoliaChainSelector = 3478487238524512106;
        uint64 ethSepoliaChainSelector = 16015286601757825753;

        uint256 balanceBefore = ccipBnM.balanceOf(address(suckerOne));

        BPTokenMapping memory map = BPTokenMapping({
            localToken: address(ccipBnM),
            minGas: 200_000,
            remoteToken: address(ccipBnM),
            remoteSelector: arbSepoliaChainSelector,
            minBridgeAmount: 1
        });

        vm.prank(multisig());
        suckerOne.mapToken(map);

        vm.startPrank(user);
        ccipBnM.approve(address(jbMultiTerminal()), amountToSend);

        // We receive 500 project tokens as a result
        uint256 projectTokenAmount = jbMultiTerminal().pay(1, address(ccipBnM), amountToSend, user, 0, "", "");

        /* suckerOne.testInsertIntoTree(1e18, address(ccipBnM), amountToSend, address(suckerTwo), arbSepoliaChainSelector); */
        IERC20(address(projectOneToken)).approve(address(suckerOne), projectTokenAmount);
        suckerOne.prepare(projectTokenAmount, user, amountToSend / 2, address(ccipBnM), arbSepoliaChainSelector);
        vm.stopPrank();

        vm.deal(sender, 1 ether);
        suckerOne.toRemote{value: 1 ether}(address(ccipBnM), arbSepoliaChainSelector);

        /* uint256 balanceAfer = ccipBnM.balanceOf(address(suckerOne));
        assertEq(balanceAfer, balanceBefore - amountToSend); */

        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        Register.NetworkDetails memory arbSepoliaNetworkDetails =
            ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        BurnMintERC677Helper ccipBnMArbSepolia = BurnMintERC677Helper(arbSepoliaNetworkDetails.ccipBnMAddress);

        assertEq(ccipBnMArbSepolia.balanceOf(address(suckerOne)), amountToSend / 2);

        // Inbox address is zero because tokens aren't mapped- this is the most simple verification that messages are being sent and received though!
        BPInboxTreeRoot memory updatedInbox = suckerOne.getInbox(address(ccipBnM), ethSepoliaChainSelector);
        assertNotEq(updatedInbox.root, bytes32(0));
    }
}
