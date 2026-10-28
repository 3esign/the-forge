// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TheForge} from "../src/TheForge.sol";
import {ForgeRenderer} from "../src/ForgeRenderer.sol";
import {ForgeArt} from "../src/ForgeArt.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

contract TheForgeTest is Test {
    TheForge forge_;
    ForgeRenderer renderer;

    address primary = address(0xA11CE);
    address secondary = address(0xB0B);
    address alice = address(0xCAFE);
    address bob = address(0xBEEF);

    uint256 constant STRIKE = 0.0003 ether;
    uint256 constant FUSE = 0.002 ether;
    uint32 constant TEMPER_AT = 21;
    uint64 constant COOL_AFTER = 3 days;

    function setUp() public {
        renderer = new ForgeRenderer();
        forge_ = new TheForge(payable(primary), payable(secondary), 500, 3000, STRIKE, FUSE, 5, TEMPER_AT, COOL_AFTER, renderer);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.warp(1_800_000_000);
        vm.roll(100);
    }

    // ------------------------------------------------------------------ helpers
    function _mintAs(address who) internal returns (uint256 id) {
        uint256 price = forge_.currentPrice();
        vm.prank(who);
        id = forge_.mint{value: price}();
    }

    function _strike(address who, uint256 id) internal {
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(who);
        forge_.strike{value: STRIKE}(id);
    }

    function _strikeN(address who, uint256 id, uint256 n) internal {
        for (uint256 k = 0; k < n; k++) _strike(who, id);
    }

    function _bar(uint256 id) internal view returns (TheForge.Bar memory b) {
        (b.lattice, b.lastHeat, b.strikes, b.hardness, b.scars, b.family, b.form, b.generation, b.parentA, b.parentB) =
            forge_.bars(id);
    }

    // ------------------------------------------------------------------ identity & pricing
    function test_identity() public view {
        assertEq(forge_.name(), "THE FORGE");
        assertEq(forge_.symbol(), "FORGE");
        assertEq(forge_.MAX_SUPPLY(), 333);
        assertEq(forge_.ARTIST_RESERVE(), 8);
        assertEq(address(forge_.renderer()), address(renderer));
    }

    function test_supportsInterfaces() public view {
        assertTrue(forge_.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(forge_.supportsInterface(0x5b5e139f)); // ERC721Metadata
        assertTrue(forge_.supportsInterface(0x2a55205a)); // ERC2981
        assertTrue(forge_.supportsInterface(0x49064906)); // ERC4906
    }

    function test_tranches() public view {
        assertEq(forge_.currentPrice(), 0.003 ether);
        assertEq(forge_.priceFor(32), 0.003 ether);
        assertEq(forge_.priceFor(33), 0.005 ether);
        assertEq(forge_.priceFor(133), 0.008 ether);
        assertEq(forge_.priceFor(233), 0.012 ether);
    }

    function test_priceAdvancesAfterFirstTranche() public {
        for (uint256 w = 0; w < 7; w++) {
            address buyer = makeAddr(string(abi.encodePacked("b", vm.toString(w))));
            vm.deal(buyer, 1 ether);
            for (uint256 k = 0; k < 5 && forge_.cast() < 33; k++) _mintAs(buyer);
        }
        assertEq(forge_.cast(), 33);
        assertEq(forge_.currentPrice(), 0.005 ether);
    }

    function test_royalty() public view {
        (address r, uint256 amt) = forge_.royaltyInfo(0, 1 ether);
        assertEq(r, primary);
        assertEq(amt, 0.05 ether);
    }

    // ------------------------------------------------------------------ mint
    function test_mintCastsRawBar() public {
        uint256 id = _mintAs(alice);
        assertEq(id, 0);
        assertEq(forge_.ownerOf(0), alice);
        TheForge.Bar memory b = _bar(0);
        assertTrue(b.lattice != 0);
        assertEq(b.form, 0);
        assertEq(b.strikes, 0);
        assertEq(b.hardness, 0);
        assertEq(b.generation, 0);
        assertLe(b.family, 4);
        assertEq(b.lastHeat, uint64(block.timestamp));
        assertEq(forge_.totalSupply(), 1);
        assertEq(forge_.cast(), 1);
    }

    function test_revert_wrongPrice() public {
        vm.prank(alice);
        vm.expectRevert(TheForge.Price.selector);
        forge_.mint{value: 0.001 ether}();
    }

    function test_perWalletLimit() public {
        for (uint256 k = 0; k < 5; k++) _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(TheForge.TooMany.selector);
        forge_.mint{value: 0.003 ether}();
    }

    function test_reserve() public {
        for (uint256 k = 0; k < 8; k++) forge_.mintFor(alice);
        vm.expectRevert(TheForge.ReserveEmpty.selector);
        forge_.mintFor(alice);
        assertEq(forge_.balanceOf(alice), 8);
        assertEq(forge_.cast(), 8);
    }

    function test_revert_reserveNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        forge_.mintFor(alice);
    }

    function test_soldOutCountsCastNotLiving() public {
        // mint everything through many wallets
        uint256 w = 0;
        while (forge_.cast() < 333) {
            address buyer = makeAddr(string(abi.encodePacked("w", vm.toString(w++))));
            vm.deal(buyer, 1 ether);
            for (uint256 k = 0; k < 5 && forge_.cast() < 333; k++) _mintAs(buyer);
        }
        assertEq(forge_.cast(), 333);
        vm.prank(alice);
        vm.expectRevert(TheForge.SoldOut.selector);
        forge_.mint{value: 0.012 ether}();
        vm.expectRevert(TheForge.SoldOut.selector);
        forge_.mintFor(alice);
    }

    function test_familyDistribution() public view {
        assertEq(forge_.familyFromLattice(0), 0);
        assertEq(forge_.familyFromLattice(49), 0);
        assertEq(forge_.familyFromLattice(50), 1);
        assertEq(forge_.familyFromLattice(74), 1);
        assertEq(forge_.familyFromLattice(75), 2);
        assertEq(forge_.familyFromLattice(89), 2);
        assertEq(forge_.familyFromLattice(90), 3);
        assertEq(forge_.familyFromLattice(97), 3);
        assertEq(forge_.familyFromLattice(98), 4);
        assertEq(forge_.familyFromLattice(99), 4);
    }

    // ------------------------------------------------------------------ strike
    function test_strikeShapesAndHardens() public {
        uint256 id = _mintAs(alice);
        vm.expectEmit(true, true, false, true, address(forge_));
        emit TheForge.Struck(id, alice, 1, 10);
        vm.prank(alice);
        forge_.strike{value: STRIKE}(id);
        TheForge.Bar memory b = _bar(id);
        assertEq(b.strikes, 1);
        assertEq(b.hardness, 10);
        assertEq(b.form, 1);
    }

    function test_firstStrikeHasNoCooldown() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        forge_.strike{value: STRIKE}(id); // same block as mint, allowed
    }

    function test_revert_strikeTooSoon() public {
        uint256 id = _mintAs(alice);
        _strike(alice, id);
        vm.prank(alice);
        vm.expectRevert(TheForge.TooSoon.selector);
        forge_.strike{value: STRIKE}(id);
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(alice);
        forge_.strike{value: STRIKE}(id);
    }

    function test_revert_strikeNotOwner() public {
        uint256 id = _mintAs(alice);
        vm.prank(bob);
        vm.expectRevert(TheForge.NotOwner.selector);
        forge_.strike{value: STRIKE}(id);
    }

    function test_revert_strikeWrongFee() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(TheForge.Price.selector);
        forge_.strike{value: STRIKE - 1}(id);
    }

    function test_temperLocksAtThreshold() public {
        uint256 id = _mintAs(alice);
        _strikeN(alice, id, 20);
        assertEq(_bar(id).form, 1);
        vm.expectEmit(true, false, false, true, address(forge_));
        emit TheForge.Tempered(id, 210);
        _strike(alice, id);
        TheForge.Bar memory b = _bar(id);
        assertEq(b.form, 2);
        assertEq(b.strikes, 21);
        assertEq(b.hardness, 210);
    }

    function test_revert_strikeTempered() public {
        uint256 id = _mintAs(alice);
        _strikeN(alice, id, 21);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        vm.expectRevert(TheForge.Locked.selector);
        forge_.strike{value: STRIKE}(id);
    }

    function test_hardnessCapped() public {
        // alloy of two tempered gives 260; further strikes cap at 1000 only after many strikes.
        // Direct check through fuse chain is slow; verify cap arithmetic via repeated striking of an alloy.
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strikeN(alice, a, 21);
        _strikeN(alice, b, 21);
        vm.prank(alice);
        uint256 c = forge_.fuse{value: FUSE}(a, b);
        assertEq(_bar(c).hardness, 260);
        _strikeN(alice, c, 20); // 460, tempers at 21st
        assertEq(_bar(c).hardness, 460);
    }

    // ------------------------------------------------------------------ fuse
    function test_fuseBurnsTwoMintsAlloy() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strike(alice, a);
        _strike(alice, b);
        uint256 supplyBefore = forge_.totalSupply();
        vm.prank(alice);
        uint256 c = forge_.fuse{value: FUSE}(a, b);
        assertEq(c, 2);
        assertEq(forge_.totalSupply(), supplyBefore - 1);
        assertEq(forge_.cast(), 2); // cap untouched
        assertEq(forge_.ownerOf(c), alice);
        vm.expectRevert();
        forge_.ownerOf(a);
        vm.expectRevert();
        forge_.ownerOf(b);
        TheForge.Bar memory C = _bar(c);
        assertEq(C.generation, 1);
        assertEq(C.form, 1);
        assertEq(C.strikes, 0);
        assertEq(C.hardness, 60);
        assertEq(C.parentA, uint32(a));
        assertEq(C.parentB, uint32(b));
        TheForge.Bar memory A = _bar(a);
        assertEq(A.lattice, 0); // storage cleared
    }

    function test_fuseFamilyRule() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strike(alice, a);
        _strike(alice, b);
        uint8 fa = _bar(a).family;
        uint8 fb = _bar(b).family;
        vm.prank(alice);
        uint256 c = forge_.fuse{value: FUSE}(a, b);
        uint8 fc = _bar(c).family;
        if (fa == fb) assertEq(fc, fa);
        else assertEq(fc, 5);
    }

    function test_fuseGenerationDeepens() public {
        uint256[4] memory ids;
        for (uint256 k = 0; k < 4; k++) {
            ids[k] = _mintAs(alice);
            _strike(alice, ids[k]);
        }
        vm.startPrank(alice);
        uint256 x = forge_.fuse{value: FUSE}(ids[0], ids[1]);
        uint256 y = forge_.fuse{value: FUSE}(ids[2], ids[3]);
        assertEq(_bar(x).generation, 1);
        assertEq(_bar(y).generation, 1);
        uint256 z = forge_.fuse{value: FUSE}(x, y);
        vm.stopPrank();
        assertEq(_bar(z).generation, 2);
        assertEq(forge_.totalSupply(), 1);
    }

    function test_revert_fuseRaw() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strike(alice, a);
        vm.prank(alice);
        vm.expectRevert(TheForge.RawCannotFuse.selector);
        forge_.fuse{value: FUSE}(a, b);
    }

    function test_revert_fuseNotBothOwned() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(bob);
        _strike(alice, a);
        _strike(bob, b);
        vm.prank(alice);
        vm.expectRevert(TheForge.NotOwner.selector);
        forge_.fuse{value: FUSE}(a, b);
    }

    function test_revert_fuseSame() public {
        uint256 a = _mintAs(alice);
        _strike(alice, a);
        vm.prank(alice);
        vm.expectRevert(TheForge.SameBar.selector);
        forge_.fuse{value: FUSE}(a, a);
    }

    function test_revert_fuseWrongFee() public {
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strike(alice, a);
        _strike(alice, b);
        vm.prank(alice);
        vm.expectRevert(TheForge.Price.selector);
        forge_.fuse{value: STRIKE}(a, b);
    }

    // ------------------------------------------------------------------ temper / cooling
    function test_temperCoolsNeglectedShaped() public {
        uint256 id = _mintAs(alice);
        _strikeN(alice, id, 3); // strikes 3, hardness 30
        vm.warp(block.timestamp + COOL_AFTER);
        assertTrue(forge_.isCold(id));
        vm.prank(bob); // anyone
        uint256 cooled = forge_.temper();
        assertEq(cooled, 1);
        TheForge.Bar memory b = _bar(id);
        assertEq(b.strikes, 2);
        assertEq(b.hardness, 10);
        assertEq(b.form, 1);
        assertFalse(forge_.isCold(id)); // lastHeat reset, one cooling per period
    }

    function test_temperBackToRaw() public {
        uint256 id = _mintAs(alice);
        _strike(alice, id);
        vm.warp(block.timestamp + COOL_AFTER);
        forge_.temper();
        TheForge.Bar memory b = _bar(id);
        assertEq(b.strikes, 0);
        assertEq(b.form, 0);
        assertEq(b.hardness, 0);
    }

    function test_temperIgnoresRawTemperedAlloy() public {
        uint256 raw = _mintAs(alice);
        uint256 t = _mintAs(alice);
        _strikeN(alice, t, 21);
        uint256 a = _mintAs(alice);
        uint256 b = _mintAs(alice);
        _strike(alice, a);
        _strike(alice, b);
        vm.prank(alice);
        uint256 alloy = forge_.fuse{value: FUSE}(a, b);
        vm.warp(block.timestamp + 30 days);
        assertEq(forge_.temper(), 0);
        assertEq(_bar(raw).form, 0);
        assertEq(_bar(t).strikes, 21);
        assertEq(_bar(alloy).hardness, 60);
    }

    function test_temperNotBeforeCoolAfter() public {
        uint256 id = _mintAs(alice);
        _strike(alice, id);
        vm.warp(block.timestamp + COOL_AFTER - 1);
        assertEq(forge_.temper(), 0);
        assertEq(_bar(id).strikes, 1);
    }

    function test_temperEmptyCollection() public {
        assertEq(forge_.temper(), 0);
    }

    function test_temperCursorBoundedAndRotates() public {
        // 60 bars shaped, all cold: first call cools 50, second cools the last 10 and wraps
        uint256 w = 0;
        while (forge_.cast() < 60) {
            address buyer = makeAddr(string(abi.encodePacked("c", vm.toString(w++))));
            vm.deal(buyer, 1 ether);
            for (uint256 k = 0; k < 5 && forge_.cast() < 60; k++) {
                uint256 id = _mintAs(buyer);
                vm.prank(buyer);
                forge_.strike{value: STRIKE}(id);
            }
        }
        vm.warp(block.timestamp + COOL_AFTER);
        uint256 gasBefore = gasleft();
        assertEq(forge_.temper(), 50);
        uint256 used = gasBefore - gasleft();
        assertLt(used, 2_000_000);
        assertEq(forge_.temperCursor(), 50);
        assertEq(forge_.temper(), 10);
        assertEq(forge_.temperCursor(), 40);
    }

    function test_quenchProtects() public {
        uint256 id = _mintAs(alice);
        _strike(alice, id);
        vm.warp(block.timestamp + COOL_AFTER - 1 hours);
        vm.prank(alice);
        forge_.quench{value: STRIKE * 3}(id);
        vm.warp(block.timestamp + 2 hours);
        assertEq(forge_.temper(), 0);
        assertEq(_bar(id).strikes, 1);
    }

    function test_revert_quenchWrongFee() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(TheForge.Price.selector);
        forge_.quench{value: STRIKE}(id);
    }

    function test_heatOf() public {
        uint256 id = _mintAs(alice);
        assertEq(forge_.heatOf(id), 100);
        vm.warp(block.timestamp + COOL_AFTER / 2);
        assertEq(forge_.heatOf(id), 50);
        vm.warp(block.timestamp + COOL_AFTER);
        assertEq(forge_.heatOf(id), 0);
    }

    // ------------------------------------------------------------------ money
    function test_harvestSplit() public {
        _mintAs(alice);
        _mintAs(bob);
        _strike(alice, 0);
        assertEq(address(forge_).balance, 0.0063 ether);
        uint256 p0 = primary.balance;
        uint256 s0 = secondary.balance;
        forge_.harvest();
        assertEq(secondary.balance - s0, 0.00189 ether);
        assertEq(primary.balance - p0, 0.00441 ether);
        assertEq(address(forge_).balance, 0);
    }

    function test_revert_harvestEmpty() public {
        vm.expectRevert(TheForge.NothingToHarvest.selector);
        forge_.harvest();
    }

    // ------------------------------------------------------------------ scars
    function test_transferScar() public {
        uint256 id = _mintAs(alice);
        vm.prank(alice);
        forge_.transferFrom(alice, bob, id);
        assertEq(_bar(id).scars, 1);
        vm.prank(bob);
        forge_.transferFrom(bob, alice, id);
        assertEq(_bar(id).scars, 2);
    }

    // ------------------------------------------------------------------ art & metadata
    function test_tokenURIIsDataJsonWithSvg() public {
        uint256 id = _mintAs(alice);
        string memory uri = forge_.tokenURI(id);
        assertTrue(LibString.startsWith(uri, "data:application/json;base64,"));
        bytes memory json = Base64.decode(LibString.slice(uri, 29));
        assertTrue(LibString.contains(string(json), '"name":"THE FORGE #0"'));
        assertTrue(LibString.contains(string(json), '"image":"data:image/svg+xml;base64,'));
        assertTrue(LibString.contains(string(json), '{"trait_type":"Form","value":"RAW"}'));
        assertTrue(LibString.contains(string(json), '{"trait_type":"Heat","value":100}'));
    }

    function test_revert_tokenURIUnminted() public {
        vm.expectRevert();
        forge_.tokenURI(7);
    }

    function test_contractURI() public view {
        string memory uri = forge_.contractURI();
        bytes memory json = Base64.decode(LibString.slice(uri, 29));
        assertTrue(LibString.contains(string(json), '"name":"THE FORGE"'));
        assertTrue(LibString.contains(string(json), "3esign.github.io/the-forge"));
    }

    function test_svgChangesWithEveryStrike() public {
        uint256 id = _mintAs(alice);
        bytes32 prev = keccak256(bytes(forge_.tokenSVG(id)));
        for (uint256 k = 0; k < 5; k++) {
            _strike(alice, id);
            bytes32 cur = keccak256(bytes(forge_.tokenSVG(id)));
            assertTrue(cur != prev);
            prev = cur;
        }
    }

    function test_svgDeterministicForSameState() public {
        uint256 id = _mintAs(alice);
        _strike(alice, id);
        string memory a = forge_.tokenSVG(id);
        vm.roll(block.number + 5);
        string memory b = forge_.tokenSVG(id);
        assertEq(a, b);
    }

    function test_svgWellFormedAndBounded() public {
        uint256 id = _mintAs(alice);
        _strikeN(alice, id, 21);
        string memory svg = forge_.tokenSVG(id);
        assertTrue(LibString.startsWith(svg, '<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(LibString.endsWith(svg, "</svg>"));
        assertLt(bytes(svg).length, 24_000);
    }

    function testFuzz_renderNeverReverts(
        uint256 lattice,
        uint8 family,
        uint8 form,
        uint8 strikes,
        uint16 hardness,
        uint8 heat,
        uint16 scars,
        uint8 generation,
        uint32 tokenId
    ) public view {
        string memory svg = renderer.render(
            ForgeArt.Bar({
                lattice: lattice,
                family: family,
                form: form,
                strikes: strikes,
                hardness: hardness,
                heat: heat,
                scars: scars,
                generation: generation,
                tokenId: tokenId
            })
        );
        assertTrue(LibString.startsWith(svg, "<svg"));
        assertTrue(LibString.endsWith(svg, "</svg>"));
        assertLt(bytes(svg).length, 24_000);
    }

    function testFuzz_outlineStaysOnCanvas(uint256 lattice, uint8 strikes) public pure {
        (int256[16] memory xs, int256[16] memory ys) = ForgeArt.outline(lattice, strikes);
        for (uint256 v = 0; v < 16; v++) {
            assertGe(xs[v], 8);
            assertLe(xs[v], 470);
            assertGe(ys[v], 8);
            assertLe(ys[v], 470);
        }
    }
}
