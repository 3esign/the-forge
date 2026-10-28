// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TheForge} from "../src/TheForge.sol";

/// @notice Live probe of a deployed TheForge (testnet). Exercises every state-changing path
///         the public will use, from the deployer/owner key, recycling fees via harvest()
///         because the treasury is the same wallet on testnet.
///  env: PRIVATE_KEY, FORGE
contract Probe is Script {
    function run() external {
        address me = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        TheForge f = TheForge(payable(vm.envAddress("FORGE")));
        uint256 sf = f.strikeFee();
        uint256 ff = f.fuseFee();
        uint256 qf = f.quenchFee();
        console.log("signer", me, "balance", me.balance);

        vm.startBroadcast(me);
        // 1. owner reserve mint: four bars
        uint256 a = f.mintFor(me);
        uint256 b = f.mintFor(me);
        uint256 c = f.mintFor(me);
        uint256 d = f.mintFor(me);
        // 2. one hammer blow each on a, b, c: raw -> shaped
        f.strike{value: sf}(a);
        f.strike{value: sf}(b);
        f.strike{value: sf}(c);
        f.harvest();
        // 3. fuse b + c into an alloy (burns both)
        uint256 alloy = f.fuse{value: ff}(b, c);
        f.harvest();
        // 4. quench d without striking
        f.quench{value: qf}(d);
        f.harvest();
        // 5. cooling pass (nothing is cold yet, must be a no-op)
        uint256 cooled = f.temper();
        vm.stopBroadcast();

        console.log("bars", a, b, c);
        console.log("bar d", d, "alloy", alloy);
        console.log("cooled", cooled);
        console.log("cast", f.cast(), "living", f.totalSupply());
        console.log("nextId", f.nextId(), "currentPrice", f.currentPrice());
        console.log("uri0 bytes", bytes(f.tokenURI(a)).length);
        console.log("uriAlloy bytes", bytes(f.tokenURI(alloy)).length);
        console.log("contractURI bytes", bytes(f.contractURI()).length);
        console.log("balance after", me.balance);
    }
}
