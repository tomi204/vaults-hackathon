// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SuperVault} from "../src/SuperVault.sol";

contract SuperVaultTest is Test {
    SuperVault public superVault;

    function setUp() public {
        superVault = new SuperVault();
    }
}
