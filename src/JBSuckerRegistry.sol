// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {JBOwnable} from "@bananapus/ownable/src/JBOwnable.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {IJBSucker} from "./interfaces/IJBSucker.sol";
import {IJBSuckerRegistry} from "./interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "./structs/JBSuckerDeployerConfig.sol";
import {JBSuckersPair} from "./structs/JBSuckersPair.sol";

contract JBSuckerRegistry is JBOwnable, IJBSuckerRegistry {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSuckerRegistry_InvalidDeployer();

    //*********************************************************************//
    // ------------------------- internal constants ----------------------- //
    //*********************************************************************//

    /// @notice A constant indicating that this sucker exists and belongs to a specific project.
    uint256 internal constant _SUCKER_EXISTS = 1;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Tracks whether the specified sucker deployer is approved by this registry.
    /// @custom:member deployer The address of the deployer to check.
    mapping(address deployer => bool) public override suckerDeployerIsAllowed;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Tracks the suckers for the specified project.
    mapping(uint256 => EnumerableMap.AddressToUintMap) internal _suckersOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param permissions A contract storing permissions.
    /// @param projects A contract which mints ERC-721s that represent project ownership and transfers.
    /// @param initialOwner The initial owner of this contract.
    constructor(IJBPermissions permissions, IJBProjects projects, address initialOwner)
        JBOwnable(projects, permissions, address(initialOwner), 0)
    {}

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Returns true if the specified sucker belongs to the specified project, and was deployed through this registry.
    /// @param projectId The ID of the project to check for.
    /// @param addr The address of the sucker to check.
    /// @return flag A flag indicating if the sucker belongs to the project, and was deployed through this registry.
    function isSuckerOf(uint256 projectId, address addr) external override view returns (bool) {
        return _suckersOf[projectId].get(addr) == _SUCKER_EXISTS;
    }

    /// @notice Gets all of the specified project's suckers which were deployed through this registry.
    /// @param projectId The ID of the project to get the suckers of.
    /// @return suckers The addresses of the suckers.
    function suckersOf(uint256 projectId) external override view returns (address[] memory) {
        return _suckersOf[projectId].keys();
    }

    /// @notice Helper function for retrieving the projects suckers and their metadata.
    /// @param projectId The ID of the project to get the suckers of.
    /// @return pairs The pairs of suckers and their metadata.
    function getSuckerPairs(uint256 projectId) external view returns (JBSuckersPair[] memory pairs) {
        // Get the suckers of the project.
        address[] memory suckers = _suckersOf[projectId].keys();

        // Keep a reference to the number of suckers.
        uint256 numberOfSuckers = suckers.length;

        // Initialize the array of pairs.
        pairs = new JBSuckersPair[](numberOfSuckers);

        // Populate the array of pairs.
        for (uint256 i; i < numberOfSuckers; i++) {
            // Get the sucker being iterated over.
            IJBSucker sucker = IJBSucker(suckers[i]);

            // slither-disable-next-line calls-loop
            pairs[i] =
                JBSuckersPair({local: address(sucker), remote: sucker.PEER(), remoteChainId: sucker.peerChainID()});
        }
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Adds a suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployer The address of the deployer to add.
    function allowSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = true;
        emit SuckerDeployerAllowed({deployer: deployer, caller: msg.sender});
    }

    /// @notice Adds multiple suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployers The address of the deployer to add.
    function allowSuckerDeployers(address[] calldata deployers) public onlyOwner {
        
        // Keep a reference to the number of deployers.
        uint256 numberOfDeployers = deployers.length;

        // Keep a reference to the deployer being iterated over.
        address deployer;

        // Iterate through the deployers and allow them.
        for (uint256 i; i < numberOfDeployers; i++) {
            // Get the deployer being iterated over.
            deployer = deployers[i];

            // Allow the deployer.
            suckerDeployerIsAllowed[deployer] = true;
            emit SuckerDeployerAllowed({deployer: deployer, caller: msg.sender});
        }
    }

    /// @notice Deploy one or more suckers for the specified project.
    /// @dev The caller must be the project's owner or have `JBPermissionIds.DEPLOY_SUCKERS` from the project's owner.
    /// @param projectId The ID of the project to deploy suckers for.
    /// @param salt The salt used to deploy the contract. For the suckers to be peers, this must be the same value on each chain where suckers are deployed.
    /// @param configurations The sucker deployer configs to use to deploy the suckers.
    /// @return suckers The addresses of the deployed suckers.
    function deploySuckersFor(uint256 projectId, bytes32 salt, JBSuckerDeployerConfig[] calldata configurations)
        public
        override
        returns (address[] memory suckers)
    {
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.DEPLOY_SUCKERS
        });

        // Create an array to store the suckers as they are deployed.
        suckers = new address[](configurations.length);

        // Calculate the salt using the sender's address and the provided `salt`.
        // This means that for suckers to be peers, the sender has to be the same on each chain.
        salt = keccak256(abi.encode(msg.sender, salt));

        // Keep a reference to the number of configurations.
        uint256 numberOfConfigurations = configurations.length;

        // Keep a reference to the configuration being iterated over.
        JBSuckerDeployerConfig memory configuration;

        // Iterate through the configurations and deploy the suckers.
        for (uint256 i; i < numberOfConfigurations; i++) {
            // Get the configuration being iterated over.
            configuration = configurations[i];

            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configuration.deployer)]) {
                revert JBSuckerRegistry_InvalidDeployer();
            }

            // Create the sucker.
            // slither-disable-next-line reentrancy-event,calls-loop
            IJBSucker sucker = configuration.deployer.createForSender({localProjectId: projectId, salt: salt});
            suckers[i] = address(sucker);

            // Store the sucker as being deployed for this project.
            // slither-disable-next-line unused-return
            _suckersOf[projectId].set(address(sucker), _SUCKER_EXISTS);

            // Map the tokens for the sucker.
            // slither-disable-next-line reentrancy-events,calls-loop
            sucker.mapTokens(configuration.mappings);
            emit SuckerDeployedFor({projectId: projectId, sucker: address(sucker), configuration: configuration, caller: msg.sender});
        }
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    function _emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId)
        internal
        virtual
        override
    {
        // Only emit after the initial transfer.
        if (address(this).code.length != 0) {
            emit OwnershipTransferred({previousOwner: previousOwner, newOwner: newProjectId == 0 ? newOwner : PROJECTS.ownerOf(newProjectId)});
        }
    }
}
