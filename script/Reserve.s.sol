// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TheForge} from "../src/TheForge.sol";

/// @notice Mainnet finish: mint the full artist reserve to the deployer, then renounce ownership.
///  env: PRIVATE_KEY, FORGE
contract Reserve is Script {
    function run() external {
        address me = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        TheForge f = TheForge(payable(vm.envAddress("FORGE")));
        uint256 n = f.ARTIST_RESERVE() - f.reserveMinted();
        vm.startBroadcast(me);
        for (uint256 i = 0; i < n; i++) f.mintFor(me);
        f.renounceOwnership();
        vm.stopBroadcast();
        console.log("reserve minted:", f.reserveMinted(), "owner:", f.owner());
    }
}
