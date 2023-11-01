// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {BPSucker, IJBDirectory, IJBTokenStore, IJBToken} from "../src/BPSucker.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBConstants.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import {IJBOperatorStore, JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";

import "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";

import {MockMessenger} from "./mocks/MockMessenger.sol";

contract BPSuckerTest is Test {
    BPSucker public suckerL1;
    BPSucker public suckerL2;


    IJBController3_1 CONTROLLER;
    IJBDirectory DIRECTORY;
    IJBTokenStore TOKENSTORE;
    IJBOperatorStore OPERATORSTORE;
    IJBPayoutRedemptionPaymentTerminal3_1 ETH_TERMINAL;

    MockMessenger _mockMessenger;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth"); // Will start on latest block by default

        CONTROLLER = IJBController3_1(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBController3_1.json"),
                ".address"
            )
        );

        DIRECTORY = IJBDirectory(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBDirectory.json"),
                ".address"
            )
        );

        TOKENSTORE = IJBTokenStore(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBTokenStore.json"),
                ".address"
            )
        );

        OPERATORSTORE = IJBOperatorStore(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBOperatorStore.json"),
                ".address"
            )
        );

        ETH_TERMINAL = IJBPayoutRedemptionPaymentTerminal3_1(
            stdJson.readAddress(
                vm.readFile("./node_modules/@jbx-protocol/juice-contracts-v3/deployments/mainnet/JBETHPaymentTerminal3_1_2.json"),
                ".address"
            )
        );

        // Configure a mock manager that mocks the OP bridge
        _mockMessenger = new MockMessenger();

        // Get the determenistic addresses for the suckers
        uint256 _nonce = vm.getNonce(address(this));
        address _suckerL1 = computeCreateAddress(address(this), _nonce);
        address _suckerL2 = computeCreateAddress(address(this), _nonce + 1);

        // Configure the pair of suckers
        suckerL1 = new BPSucker(
            _mockMessenger,
            DIRECTORY,
            TOKENSTORE,
            OPERATORSTORE,
            _suckerL2
        );
        suckerL2 = new BPSucker(
            _mockMessenger,
            DIRECTORY,
            TOKENSTORE,
            OPERATORSTORE,
            _suckerL1
        );
    }

    function test_MetaSuckersLinked() public {
        assertEq(
            suckerL1.PEER(),
            address(suckerL2)
        );

         assertEq(
            suckerL2.PEER(),
            address(suckerL1)
        );
    }

    function test_linkProjects() public {
        address _L1ProjectOwner = makeAddr('L1ProjectOwner');
        address _L2ProjectOwner = makeAddr('L2ProjectOwner');

        (uint256 _L1Project, uint256 _L2Project) = _configureAndLinkProjects(_L1ProjectOwner, _L2ProjectOwner);

        assertEq(
            suckerL1.acceptFromRemote(_L1Project),
            _L2Project
        );

        assertEq(
            suckerL2.acceptFromRemote(_L2Project),
            _L1Project
        );
    }

    function test_suck_L2toL1(
        uint256 _payAmount
    ) public {
        _payAmount = _bound(_payAmount, 0.1 ether, 100_000 ether);

        address _L1ProjectOwner = makeAddr('L1ProjectOwner');
        address _L2ProjectOwner = makeAddr('L2ProjectOwner');

        // Configure the projects and suckers
        (uint256 _L1Project, uint256 _L2Project) = _configureAndLinkProjects(_L1ProjectOwner, _L2ProjectOwner);

        // Fund the user
        address _user = makeAddr('user');
        vm.deal(_user, _payAmount);

        // User pays project and receives tokens in exchange on L2
        vm.startPrank(_user);
        uint256 _receivedTokens = ETH_TERMINAL.pay{value: _payAmount}(
            _L2Project,
            _payAmount,
            JBTokens.ETH,
            address(_user),
            0,
            true,
            "",
            bytes("")
        );

        // Give sucker allowance to spend our token
        IJBToken _l1Token = TOKENSTORE.tokenOf(_L1Project);
        IJBToken _l2Token = TOKENSTORE.tokenOf(_L2Project);
        _l2Token.approve(_L2Project, address(suckerL2), _receivedTokens);

        // Expect the L1 terminal to receive the funds
        vm.expectCall(
            address(ETH_TERMINAL),
            abi.encodeWithSelector(
                IJBPaymentTerminal.addToBalanceOf.selector,
                _L1Project,
                _payAmount,
                JBTokens.ETH,
                string(""),
                bytes("")
            )
        );
        
        // Redeem tokens on the L2 and mint them on L1, moving the backing assets with it.
        suckerL2.toRemote(
            _L2Project,
            _receivedTokens,
            _user,
            0
        );
        
        // Balance should now be present on L1
        assertEq( _l1Token.balanceOf(_user, _L1Project), _receivedTokens);
        // User should no longer have any tokens on L2
        assertEq( _l2Token.balanceOf(_user, _L2Project), 0);
    }

    function _configureAndLinkProjects(
       address _L1ProjectOwner,
       address _L2ProjectOwner
    ) internal returns (uint256 _L1Project, uint256 _L2Project) {
        // Deploy two projects
        _L1Project = _deployJBProject(_L1ProjectOwner, "Bananapus", "NANA");
        _L2Project = _deployJBProject(_L2ProjectOwner, "BananapusOptimism", "OPNANA");

        uint256[] memory _permissions = new uint256[](1);
        _permissions[0] = JBOperations.MINT;

        // Grant 'MINT' permission to the JBSuckers of their localChains
        vm.prank(_L1ProjectOwner);
        OPERATORSTORE.setOperator(JBOperatorData({
            operator: address(suckerL1),
            domain: _L1Project,
            permissionIndexes: _permissions
        }));

        vm.prank(_L2ProjectOwner);
        OPERATORSTORE.setOperator(JBOperatorData({
            operator: address(suckerL2),
            domain: _L2Project,
            permissionIndexes: _permissions
        }));

        // Register the remote projects to each-other
        _linkProjects(_L1Project, _L2Project);
    }


    function _deployJBProject(
        address _owner,
        string memory _tokenName,
        string memory _tokenSymbol
    ) internal returns(uint256 _projectId) {

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = IJBPaymentTerminal(address(ETH_TERMINAL));

        // Create project
        _projectId = CONTROLLER.launchProjectFor(
            _owner,
            JBProjectMetadata({
                content: "",
                domain: 0
            }),
            JBFundingCycleData({
                duration: 0,
                weight: 10 ** 18,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: true,
                    allowSetController: true,
                    pauseTransfers: false
                }),
                reservedRate: 0,
                redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                ballotRedemptionRate: JBConstants.MAX_REDEMPTION_RATE,
                pausePay: false,
                pauseDistributions: false,
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: true,
                allowTerminalMigration: true,
                allowControllerMigration: true,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: true,
                useDataSourceForPay: false,
                useDataSourceForRedeem: false,
                dataSource: address(0),
                metadata: 0
            }),
            0,
            new JBGroupedSplits[](0),
            new JBFundAccessConstraints[](0),
            _terminals,
            ""
        );

        vm.prank(_owner);
        TOKENSTORE.issueFor(_projectId, _tokenName, _tokenSymbol);
    }

    function _linkProjects(
        uint256 _projectIdL1,
        uint256 _projectIdL2
    ) internal {
        IJBProjects _projects = DIRECTORY.projects();

        // Link the project on L1 to the project on L2
        vm.prank(_projects.ownerOf(_projectIdL1));
        suckerL1.register(_projectIdL1, _projectIdL2);

        // Link the project on L2 to the project on L1
        vm.prank(_projects.ownerOf(_projectIdL2));
        suckerL2.register(_projectIdL2, _projectIdL1);
    }
}
