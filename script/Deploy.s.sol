// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TheForge} from "../src/TheForge.sol";
import {ForgeRenderer} from "../src/ForgeRenderer.sol";

/// @notice Deploys ForgeRenderer then TheForge wired to it.
///
///  env: PRIVATE_KEY, TREASURY, SECONDARY_TREASURY
///  Base Sepolia:  forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
///  Base mainnet:  only on Semir's explicit order.
///
///  After deploy, on mainnet only: mintFor() the artist reserve, then renounceOwnership().
contract Deploy is Script {
    function run() external {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        address payable primary = payable(vm.envAddress("TREASURY"));
        address payable secondary = payable(vm.envAddress("SECONDARY_TREASURY"));

        vm.startBroadcast(deployer);
        ForgeRenderer renderer = new ForgeRenderer();
        TheForge forge_ = new TheForge(
            primary,
            secondary,
            500, // 5% ERC-2981 royalty
            3000, // 30% of harvested balance to secondary treasury
            0.0003 ether, // strike fee
            0.002 ether, // fuse fee
            5, // max public mints per wallet
            21, // strikes to temper
            3 days, // neglect before cooling
            renderer
        );
        vm.stopBroadcast();

        console.log("ForgeRenderer:", address(renderer));
        console.log("TheForge:", address(forge_));
        console.log("name:", forge_.name());
        console.log("currentPrice:", forge_.currentPrice());
    }
}
