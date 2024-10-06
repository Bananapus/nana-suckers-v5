// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Options for the deprecation state of a `JBSucker`.
/// @custom:element NOT_DEPRECATED The `JBSucker` is not deprecated.
/// @custom:element DEPRECATION_PENDING The `JBSucker` has a deprecation set, but it is still fully functional.
/// @custom:element SENDING_DISABLED The `JBSucker` is deprecated and sending to the pair sucker is disabled.
/// @custom:element DEPRECATED The `JBSucker` is deprecated, but it continues to let users claim their funds.
enum JBSuckerDeprecationState {
    NOT_DEPRECATED,
    DEPRECATION_PENDING,
    SENDING_DISABLED,
    DEPRECATED
}
