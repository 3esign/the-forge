// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ForgeArt} from "../src/ForgeArt.sol";

/// @notice Renders a curated set of bar states with the real on-chain renderer and
///         writes them to docs/gallery/*.svg plus docs/data/gallery.json for the
///         GitHub Pages preview. No chain, no broadcast: `forge script script/Gallery.s.sol`.
contract Gallery is Script {
    string json;
    uint256 n;

    function one(
        string memory slug,
        string memory caption,
        uint256 seed,
        uint8 family,
        uint8 form,
        uint32 strikes,
        uint16 hardness,
        uint8 heat,
        uint16 scars,
        uint8 generation
    ) internal {
        ForgeArt.Bar memory b = ForgeArt.Bar({
            lattice: uint256(keccak256(abi.encode("THE FORGE gallery", seed))),
            family: family,
            form: form,
            strikes: strikes,
            hardness: hardness,
            heat: heat,
            scars: scars,
            generation: generation,
            tokenId: seed
        });
        string memory svg = ForgeArt.render(b);
        string memory file = string.concat("docs/gallery/", slug, ".svg");
        vm.writeFile(file, svg);
        json = string.concat(
            json,
            n == 0 ? "" : ",",
            '{"file":"gallery/', slug, '.svg","caption":"', caption, '","family":"', ForgeArt.familyName(family),
            '","form":"', ForgeArt.formName(form), '","strikes":', vm.toString(strikes), ',"hardness":', vm.toString(hardness),
            ',"heat":', vm.toString(heat), ',"generation":', vm.toString(generation), ',"bytes":', vm.toString(bytes(svg).length), "}"
        );
        n++;
    }

    function run() external {
        // fresh from the furnace: one of each family, glowing, untouched
        one("01-iron-raw", "Iron, raw, fresh from the furnace", 1, 0, 0, 0, 0, 100, 0, 0);
        one("02-copper-raw", "Copper, raw, still glowing", 2, 1, 0, 0, 0, 100, 0, 0);
        one("03-silver-raw", "Silver, raw", 3, 2, 0, 0, 0, 100, 0, 0);
        one("04-gold-raw", "Gold, raw", 4, 3, 0, 0, 0, 100, 0, 0);
        one("05-meteor-raw", "Meteor, raw: olivine in the lattice", 5, 4, 0, 0, 0, 100, 0, 0);
        // the work: strikes change the outline, hardness reveals the lattice
        one("06-iron-3", "Iron after 3 strikes", 6, 0, 1, 3, 30, 100, 0, 0);
        one("07-iron-8", "Iron after 8 strikes, cooling", 6, 0, 1, 8, 80, 40, 0, 0);
        one("08-iron-15", "Iron after 15 strikes", 6, 0, 1, 15, 150, 90, 0, 0);
        one("09-copper-12", "Copper after 12 strikes", 7, 1, 1, 12, 120, 70, 0, 0);
        one("10-silver-18", "Silver after 18 strikes, almost tempered", 8, 2, 1, 18, 180, 100, 0, 0);
        one("11-gold-10", "Gold after 10 strikes", 9, 3, 1, 10, 100, 55, 0, 0);
        one("12-meteor-14", "Meteor after 14 strikes", 10, 4, 1, 14, 140, 100, 0, 0);
        // neglect: a shaped bar gone cold
        one("13-iron-cold", "Iron, shaped, left cold: ash settles", 6, 0, 1, 9, 70, 0, 0, 0);
        one("14-copper-cold", "Copper, shaped, left cold", 7, 1, 1, 5, 30, 0, 0, 0);
        // tempered: locked forever
        one("15-iron-tempered", "Iron, tempered at 21 strikes", 11, 0, 2, 21, 210, 0, 0, 0);
        one("16-copper-tempered", "Copper, tempered", 12, 1, 2, 21, 210, 0, 0, 0);
        one("17-silver-tempered", "Silver, tempered", 13, 2, 2, 21, 210, 0, 0, 0);
        one("18-gold-tempered", "Gold, tempered", 14, 3, 2, 21, 210, 0, 0, 0);
        one("19-meteor-tempered", "Meteor, tempered", 15, 4, 2, 21, 210, 0, 0, 0);
        // alloys: fused bars carry damascus waves
        one("20-gold-alloy-g1", "Gold alloy, generation 1 (gold + gold)", 16, 3, 1, 0, 260, 100, 0, 1);
        one("21-damascus-g1", "Damascus, generation 1 (iron + copper)", 17, 5, 1, 4, 100, 80, 0, 1);
        one("22-damascus-g2", "Damascus, generation 2, shaped", 18, 5, 1, 11, 420, 100, 0, 2);
        one("23-damascus-g3-tempered", "Damascus, generation 3, tempered", 19, 5, 2, 21, 760, 0, 0, 3);
        one("24-damascus-g5-tempered", "Damascus, generation 5, tempered, hardness 1000", 20, 5, 2, 21, 1000, 0, 0, 5);
        // history on the surface: transfers scar the edge
        one("25-silver-scarred", "Silver, tempered, 6 transfers", 21, 2, 2, 21, 210, 0, 6, 0);
        one("26-iron-scarred-cold", "Iron, shaped, 3 transfers, cold", 22, 0, 1, 6, 40, 0, 3, 0);
        // collection image, same state contractURI() uses
        ForgeArt.Bar memory c = ForgeArt.Bar({
            lattice: uint256(keccak256("THE FORGE")),
            family: 3,
            form: 2,
            strikes: 21,
            hardness: 210,
            heat: 0,
            scars: 0,
            generation: 0,
            tokenId: 0
        });
        vm.writeFile("docs/gallery/collection.svg", ForgeArt.render(c));
        vm.writeFile("docs/data/gallery.json", string.concat("[", json, "]"));
    }
}
