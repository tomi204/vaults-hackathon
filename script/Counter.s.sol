// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SuperVault} from "../src/SuperVault.sol";

contract SuperVaultScript is Script {
    SuperVault public superVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // superVault = new SuperVault(
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0)
        // );

        vm.stopBroadcast();
    }
}
