// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/SuperVault.sol";

contract DeploySuperVault is Script {
    function run() external {
        // Recuperar la private key del ambiente
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Comenzar broadcast de las transacciones
        vm.startBroadcast(deployerPrivateKey);

        IERC20 asset = IERC20(vm.envAddress("ASSET_ADDRESS"));

        //
        SuperVault superVault = new SuperVault(
            vm.envAddress("ADMIN_ADDRESS"),
            asset,
            vm.envString("NAME"),
            vm.envString("SYMBOL"),
            vm.envAddress("AGENT_ADDRESS"),
            vm.envAddress("AAVE_V3_ADDRESS"),
            vm.envAddress("BALANCER_V2_ADDRESS")
        );

        address superVaultAddress = address(superVault);
        console.log("SuperVault deployed to:", superVaultAddress);

        vm.stopBroadcast();

        // Log de la dirección del contrato desplegado
        console.log("SuperVault deployed to:", address(superVault));
    }
}
