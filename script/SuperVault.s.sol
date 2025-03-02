// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/SuperVault.sol";

contract DeploySuperVault is Script {
    function run() external {
        // Retrieve private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        IERC20 asset = IERC20(vm.envAddress("ASSET_ADDRESS"));

        SuperVault superVault = new SuperVault(
            vm.envAddress("ADMIN_ADDRESS"),
            asset,
            vm.envString("NAME"),
            vm.envString("SYMBOL"),
            vm.envAddress("AGENT_ADDRESS"),
            vm.envAddress("SILO_FINANCE_ADDRESS"),
            vm.envAddress("BEETS_V2_ADDRESS")
        );

        address superVaultAddress = address(superVault);
        console.log("SuperVault deployed to:", superVaultAddress);

        vm.stopBroadcast();

        console.log("SuperVault deployed to:", address(superVault));
    }
}
