// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ForgeArt} from "./ForgeArt.sol";

/// @title ForgeRenderer — the on-chain artist, deployed once and wired as an immutable.
/// @notice Pure functions only. TheForge stores this address as `immutable`, so the art
///         can never be swapped: the renderer is as final as the collection.
contract ForgeRenderer {
    function render(ForgeArt.Bar memory b) external pure returns (string memory) {
        return ForgeArt.render(b);
    }

    function familyName(uint8 f) external pure returns (string memory) {
        return ForgeArt.familyName(f);
    }

    function formName(uint8 f) external pure returns (string memory) {
        return ForgeArt.formName(f);
    }
}
