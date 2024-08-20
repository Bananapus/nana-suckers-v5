// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBLeaf} from "./JBLeaf.sol";
import {JBSuckerConstants} from "../libraries/JBSuckerConstants.sol";

/// @custom:member token The token to claim.
/// @custom:member leaf The leaf to claim from.
/// @custom:member proof The proof to claim with. 
struct JBClaim {
    address token;
    JBLeaf leaf;
    bytes32[JBSuckerConstants.TREE_DEPTH] proof;
}
