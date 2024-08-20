// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBOptimismSucker.sol";

contract JBBaseSucker is JBOptimismSucker {
    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param permissions A contract storing permissions.
    /// @param tokens A contract that manages token minting and burning.
    /// @param peer The address of the peer sucker on the remote chain.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address peer,
        JBAddToBalanceMode addToBalanceMode
    ) JBOptimismSucker(directory, permissions, tokens, peer, addToBalanceMode) {}

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return 8453;
        if (chainId == 8453) return 1;
        if (chainId == 11155111) return 84532;
        if (chainId == 84532) return 11155111;
        return 0;
    }
}
