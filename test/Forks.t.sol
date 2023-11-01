// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {BPSucker, IJBDirectory} from "../src/BPSucker.sol";

contract BPSuckerTest is Test {
    BPSucker public sucker;

    IJBDirectory constant DIRECTORY = IJBDirectory(0x8E05bcD2812E1449f0EC3aE24E2C395F533d9A99);

    function setUp() public {
        // sucker = new BPSucker(

        // );
    }
}
