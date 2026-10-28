// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";

/// @title ForgeArt — fully on-chain SVG renderer for THE FORGE.
/// @notice A bar is drawn from its history. The outline replays every strike it ever
///         took, each strike leaves a peening dent, hardness reveals the crystal lattice,
///         heat glows from the core and fades, tempering writes oxide colours and locks a
///         bright rim, fusing writes damascus waves, transfers leave hairline scars.
///         `render()` is pure: same state, same image, forever.
/// @dev No time, block, or randomness beyond the arguments. Every loop is bounded.
library ForgeArt {
    uint256 internal constant V = 16; // vertices of the front face
    uint256 internal constant MAX_REPLAY = 64; // strikes replayed into the outline
    uint256 internal constant MAX_DENTS = 24; // most recent dents drawn
    int256 internal constant NOISE_CAP = 22; // max vertex displacement (px)
    int256 internal constant DX = 30; // top face depth, x
    int256 internal constant DY = 22; // top face depth, y

    struct Bar {
        uint256 lattice; // crystal seed, fixed at cast (or at fuse)
        uint8 family; // 0 iron 1 copper 2 silver 3 gold 4 meteor 5 damascus
        uint8 form; // 0 raw 1 shaped 2 tempered
        uint32 strikes; // hammer blows received (resets at fuse)
        uint16 hardness; // 0..1000
        uint8 heat; // 0 cold .. 100 just struck
        uint16 scars; // transfers
        uint8 generation; // 0 cast, n = fused n times
        uint256 tokenId;
    }

    struct Pal {
        uint256 hue;
        uint256 sat;
        uint256 lig;
        uint256 bgHue;
    }

    // ------------------------------------------------------------------ names
    function familyName(uint8 f) internal pure returns (string memory) {
        if (f == 0) return "IRON";
        if (f == 1) return "COPPER";
        if (f == 2) return "SILVER";
        if (f == 3) return "GOLD";
        if (f == 4) return "METEOR";
        return "DAMASCUS";
    }

    function formName(uint8 f) internal pure returns (string memory) {
        if (f == 0) return "RAW";
        if (f == 1) return "SHAPED";
        return "TEMPERED";
    }

    function palette(uint8 family) internal pure returns (Pal memory) {
        if (family == 0) return Pal(214, 9, 40, 218);
        if (family == 1) return Pal(21, 68, 47, 16);
        if (family == 2) return Pal(206, 10, 70, 208);
        if (family == 3) return Pal(43, 82, 52, 34);
        if (family == 4) return Pal(258, 24, 33, 264);
        return Pal(212, 12, 37, 204);
    }

    // ------------------------------------------------------------------ prng
    function rnd(uint256 s, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(s, i)));
    }

    // ------------------------------------------------------------------ outline
    /// @dev Base ingot front face: 16 vertices clockwise from top-left.
    function baseVertex(uint256 v) internal pure returns (int256 x, int256 y) {
        if (v < 6) return (72 + int256(v) * 68, 246); // top edge, left to right
        if (v == 6) return (420, 279);
        if (v == 7) return (420, 313);
        if (v < 14) return (412 - int256(v - 8) * 68, 346); // bottom edge, right to left
        if (v == 14) return (64, 313);
        return (64, 279);
    }

    /// @dev Replays strikes over the lattice seed: each strike nudges one vertex, every
    ///      two strikes thin and lengthen the whole bar. Returns the 16 final vertices.
    function outline(uint256 lattice, uint32 strikes)
        internal
        pure
        returns (int256[V] memory xs, int256[V] memory ys)
    {
        int256[V] memory dx;
        int256[V] memory dy;
        for (uint256 v = 0; v < V; v++) {
            uint256 r = rnd(lattice, 100 + v);
            dx[v] = int256(r % 7) - 3;
            dy[v] = int256((r >> 8) % 7) - 3;
        }
        uint256 n = strikes > MAX_REPLAY ? MAX_REPLAY : strikes;
        for (uint256 k = 1; k <= n; k++) {
            uint256 r = rnd(lattice, k);
            uint256 v = r % V;
            dx[v] = clampNoise(dx[v] + int256((r >> 8) % 15) - 7);
            dy[v] = clampNoise(dy[v] + int256((r >> 16) % 15) - 7);
        }
        int256 thin = int256(n / 2);
        if (thin > 14) thin = 14;
        for (uint256 v = 0; v < V; v++) {
            (int256 bx, int256 by) = baseVertex(v);
            int256 sx = 242 + ((bx - 242) * (1000 + thin * 6)) / 1000;
            int256 sy = by;
            if (by == 246) sy = by + thin;
            if (by == 346) sy = by - thin;
            xs[v] = clampPx(sx + dx[v]);
            ys[v] = clampPx(sy + dy[v]);
        }
    }

    function frontPoints(int256[V] memory xs, int256[V] memory ys) internal pure returns (string memory s) {
        for (uint256 v = 0; v < V; v++) {
            s = string.concat(s, i(xs[v]), ",", i(ys[v]), v + 1 < V ? " " : "");
        }
    }

    /// @dev Top face: the top edge (v0..v5) and the same edge pushed back by (DX,-DY).
    function topPoints(int256[V] memory xs, int256[V] memory ys) internal pure returns (string memory s) {
        for (uint256 v = 0; v < 6; v++) {
            s = string.concat(s, i(xs[v]), ",", i(ys[v]), " ");
        }
        for (uint256 k = 0; k < 6; k++) {
            uint256 v = 5 - k;
            s = string.concat(s, i(xs[v] + DX), ",", i(ys[v] - DY), k < 5 ? " " : "");
        }
    }

    /// @dev Right face: v5 → v6 → v7 and back along the pushed edge.
    function sidePoints(int256[V] memory xs, int256[V] memory ys) internal pure returns (string memory) {
        return string.concat(
            i(xs[5]), ",", i(ys[5]), " ", i(xs[6]), ",", i(ys[6]), " ", i(xs[7]), ",", i(ys[7]), " ",
            i(xs[7] + DX), ",", i(ys[7] - DY), " ", i(xs[6] + DX), ",", i(ys[6] - DY), " ", i(xs[5] + DX), ",", i(ys[5] - DY)
        );
    }

    // ------------------------------------------------------------------ render
    function render(Bar memory b) internal pure returns (string memory) {
        if (b.form > 2) b.form = 2;
        if (b.family > 5) b.family = 5;
        if (b.heat > 100) b.heat = 100;
        if (b.hardness > 1000) b.hardness = 1000;
        Pal memory p = palette(b.family);
        (int256[V] memory xs, int256[V] memory ys) = outline(b.lattice, b.strikes);
        string memory fp = frontPoints(xs, ys);
        string memory tp = topPoints(xs, ys);
        string memory sp = sidePoints(xs, ys);

        string memory s = defs(p, b, fp, tp, sp);
        s = string.concat(s, background(p, b));
        s = string.concat(s, faces(p, b, fp, tp, sp));
        s = string.concat(s, lattice(b));
        if (b.generation > 0) s = string.concat(s, damascus(b));
        s = string.concat(s, dents(b));
        if (b.form < 2) s = string.concat(s, heat(b));
        if (b.form == 1 && b.generation == 0 && b.heat == 0) s = string.concat(s, cold());
        if (b.form == 2) s = string.concat(s, temper(p, fp, tp));
        s = string.concat(s, scars(p, b, xs, ys));
        s = string.concat(s, sign(b));
        return string.concat(s, "</svg>");
    }

    function defs(Pal memory p, Bar memory b, string memory fp, string memory tp, string memory sp)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512"><defs>',
            gradients(p),
            patterns(p, b),
            '<clipPath id="cf"><polygon points="', fp, '"/></clipPath>',
            '<clipPath id="ca"><polygon points="', fp, '"/><polygon points="', tp, '"/><polygon points="', sp, '"/></clipPath>',
            '</defs>'
        );
    }

    function gradients(Pal memory p) internal pure returns (string memory) {
        uint256 hi = p.lig + 26 > 93 ? 93 : p.lig + 26;
        uint256 lo = p.lig > 24 ? p.lig - 22 : 2;
        uint256 top = p.lig + 16 > 90 ? 90 : p.lig + 16;
        return string.concat(
            '<radialGradient id="bg" cx="50%" cy="58%" r="68%"><stop offset="0" stop-color="hsl(',
            u(p.bgHue), ',28%,12%)"/><stop offset="1" stop-color="#040508"/></radialGradient>',
            '<linearGradient id="mf" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(',
            hsl3(p.hue, p.sat, hi), ')"/><stop offset="0.45" stop-color="hsl(', hsl3(p.hue, p.sat, p.lig),
            ')"/><stop offset="1" stop-color="hsl(', hsl3(p.hue, p.sat, lo), ')"/></linearGradient>',
            '<linearGradient id="mt" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="hsl(',
            hsl3(p.hue, p.sat, top), ')"/><stop offset="1" stop-color="hsl(', hsl3(p.hue, p.sat, hi), ')"/></linearGradient>',
            '<linearGradient id="ms" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(',
            hsl3(p.hue, p.sat, lo), ')"/><stop offset="1" stop-color="hsl(', hsl3(p.hue, p.sat, lo > 10 ? lo - 8 : 2), ')"/></linearGradient>',
            '<radialGradient id="h" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff2c0"/>',
            '<stop offset="0.35" stop-color="#ffb347"/><stop offset="0.7" stop-color="#ff5a1a" stop-opacity="0.7"/>',
            '<stop offset="1" stop-color="#ff3a00" stop-opacity="0"/></radialGradient>',
            '<radialGradient id="dn" cx="42%" cy="40%" r="60%"><stop offset="0" stop-color="#000" stop-opacity="0.38"/>',
            '<stop offset="0.6" stop-color="#000" stop-opacity="0.06"/><stop offset="0.82" stop-color="#fff" stop-opacity="0"/>',
            '<stop offset="0.94" stop-color="#fff" stop-opacity="0.5"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>',
            '<linearGradient id="ox" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2f6bff"/>',
            '<stop offset="0.35" stop-color="#d9a441"/><stop offset="0.65" stop-color="#e3c27a"/><stop offset="1" stop-color="#7a35c9"/></linearGradient>',
            '<filter id="g"><feGaussianBlur stdDeviation="9"/></filter>',
            '<filter id="s"><feGaussianBlur stdDeviation="1.4"/></filter>'
        );
    }

    /// @dev Lattice grid (angle and cell from the seed, opacity from hardness) and damascus waves.
    function patterns(Pal memory p, Bar memory b) internal pure returns (string memory) {
        uint256 hi = p.lig + 30 > 96 ? 96 : p.lig + 30;
        uint256 lat = 10 + (uint256(b.hardness) * 38) / 1000;
        uint256 ang = b.lattice % 180;
        uint256 cell = 9 + (b.lattice >> 8) % 8;
        return string.concat(
            '<pattern id="l" width="', u(cell), '" height="', u(cell), '" patternUnits="userSpaceOnUse" patternTransform="rotate(',
            u(ang), ')"><path d="M0 0H', u(cell), 'M0 0V', u(cell), '" stroke="#fff" stroke-width="0.7" fill="none"/>',
            '<circle cx="', u(cell / 2), '" cy="', u(cell / 2), '" r="0.9" fill="#fff"/></pattern>',
            '<pattern id="d" width="36" height="', u(14 - uint256(b.generation > 4 ? 4 : b.generation) * 2),
            '" patternUnits="userSpaceOnUse"><path d="M0 5q9-7 18 0t18 0" fill="none" stroke="hsl(',
            hsl3(p.hue, p.sat, hi), ')" stroke-width="1.6"/></pattern>',
            '<style>.lat{opacity:0.', pad2(lat), '}</style>'
        );
    }

    function background(Pal memory p, Bar memory b) internal pure returns (string memory s) {
        s = '<rect width="512" height="512" fill="url(#bg)"/>';
        // floor: cold stone line and a warm reflection when the bar is hot
        s = string.concat(
            s, '<rect y="392" width="512" height="120" fill="#030406" opacity="0.7"/>',
            '<path d="M0 392h512" stroke="hsl(', u(p.bgHue), ',20%,22%)" stroke-width="1"/>'
        );
        if (b.form < 2 && b.heat > 0) {
            s = string.concat(
                s, '<ellipse cx="258" cy="398" rx="210" ry="34" fill="#ff6a1a" opacity="0.', pad2((uint256(b.heat) * 30) / 100),
                '" filter="url(#g)"/>'
            );
            uint256 n = 4 + (uint256(b.heat) * 16) / 100;
            for (uint256 k = 0; k < n; k++) {
                uint256 r = rnd(b.lattice, 700 + k);
                s = string.concat(
                    s, '<circle cx="', u(40 + r % 432), '" cy="', u(30 + (r >> 9) % 330), '" r="', (r >> 20) & 1 == 0 ? "1" : "1.8",
                    '" fill="#ffa040" opacity="0.', pad2(20 + (r >> 24) % 60), '"/>'
                );
            }
        } else {
            s = string.concat(s, '<ellipse cx="258" cy="398" rx="200" ry="30" fill="hsl(', u(p.bgHue), ',30%,10%)" filter="url(#g)"/>');
        }
        // anvil block
        s = string.concat(
            s, '<path d="M118 352h276l-14 40h-248z" fill="#0a0b0f"/>',
            '<path d="M132 392h248v14h-248z" fill="#07080b"/>',
            '<path d="M118 352h276" stroke="#2b2e3a" stroke-width="1.5"/>'
        );
    }

    /// @dev Three faces: top (lit), side (shadow), front (gradient). Rim stroke grows with hardness.
    function faces(Pal memory p, Bar memory b, string memory fp, string memory tp, string memory sp)
        internal
        pure
        returns (string memory)
    {
        uint256 lo = p.lig > 32 ? p.lig - 30 : 2;
        uint256 sw = 8 + (uint256(b.hardness) * 28) / 1000; // 0.8 .. 3.6 px
        string memory edge = string.concat('stroke="hsl(', hsl3(p.hue, p.sat, lo), ')" stroke-width="', u(sw / 10), ".", u(sw % 10), '" stroke-linejoin="round"');
        return string.concat(
            '<polygon points="', fp, '" fill="#000" opacity="0.55" transform="translate(6 9)" filter="url(#s)"/>',
            '<polygon points="', tp, '" fill="url(#mt)" ', edge, "/>",
            '<polygon points="', sp, '" fill="url(#ms)" ', edge, "/>",
            '<polygon points="', fp, '" fill="url(#mf)" ', edge, "/>"
        );
    }

    /// @dev Crystal lattice on every face, revealed by hardness. Meteor carries olivine.
    function lattice(Bar memory b) internal pure returns (string memory s) {
        s = '<rect width="512" height="512" fill="url(#l)" clip-path="url(#ca)" class="lat"/>';
        if (b.family == 4) {
            for (uint256 k = 0; k < 16; k++) {
                uint256 r = rnd(b.lattice, 800 + k);
                s = string.concat(
                    s, '<circle cx="', u(70 + r % 380), '" cy="', u(230 + (r >> 10) % 112), '" r="', u(2 + (r >> 20) % 4),
                    '" fill="hsl(', u(88 + (r >> 24) % 34), ',72%,56%)" opacity="0.75" clip-path="url(#ca)"/>'
                );
            }
        }
    }

    /// @dev Damascus waves on every face: only fused bars carry them, denser with generation.
    function damascus(Bar memory b) internal pure returns (string memory) {
        uint256 op = 40 + uint256(b.generation > 4 ? 4 : b.generation) * 10;
        return string.concat('<rect width="512" height="512" fill="url(#d)" clip-path="url(#ca)" opacity="0.', pad2(op), '"/>');
    }

    /// @dev Peening dents: one per strike, lit from the upper left. The most recent 24 are drawn.
    function dents(Bar memory b) internal pure returns (string memory s) {
        uint256 n = b.strikes;
        uint256 from = n > MAX_DENTS ? n - MAX_DENTS + 1 : 1;
        for (uint256 k = from; k <= n; k++) {
            uint256 r = rnd(b.lattice, k);
            uint256 cx = 84 + (r >> 24) % 330;
            uint256 cy = 254 + (r >> 32) % 86;
            uint256 rad = 5 + (r >> 40) % 8;
            s = string.concat(
                s, '<circle cx="', u(cx), '" cy="', u(cy), '" r="', u(rad), '" fill="url(#dn)" clip-path="url(#cf)"/>'
            );
        }
    }

    /// @dev Heat: a core glow that fades with time; sparks fly off the last strike while it is fresh.
    function heat(Bar memory b) internal pure returns (string memory s) {
        if (b.heat == 0) return "";
        uint256 op = 20 + (uint256(b.heat) * 72) / 100;
        s = string.concat(
            '<rect x="40" y="200" width="430" height="170" fill="url(#h)" clip-path="url(#ca)" opacity="0.', pad2(op), '"/>'
        );
        if (b.heat >= 85 && b.strikes > 0) {
            uint256 r = rnd(b.lattice, b.strikes);
            int256 cx = int256(84 + (r >> 24) % 330);
            int256 cy = int256(254 + (r >> 32) % 86);
            for (uint256 k = 0; k < 9; k++) {
                uint256 q = rnd(b.lattice, 600 + k + b.strikes);
                int256 ex = cx + int256(q % 110) - 55;
                int256 ey = cy - int256((q >> 8) % 90) - 6;
                s = string.concat(
                    s, '<path d="M', i(cx), " ", i(cy), "L", i(ex), " ", i(ey), '" stroke="#ffd66b" stroke-width="',
                    (q >> 16) & 1 == 0 ? "0.8" : "1.4", '" opacity="0.', pad2(45 + (q >> 20) % 50), '"/>'
                );
            }
        }
    }

    /// @dev Neglect: a shaped bar left cold loses its lustre and gathers ash.
    function cold() internal pure returns (string memory) {
        return
            '<rect width="512" height="512" fill="#3c3e46" clip-path="url(#ca)" opacity="0.48"/>'
            '<rect width="512" height="512" fill="url(#l)" clip-path="url(#ca)" opacity="0.07"/>';
    }

    /// @dev Tempered: oxide colours across the faces, a bright locked rim, the hallmark.
    function temper(Pal memory p, string memory fp, string memory tp) internal pure returns (string memory) {
        uint256 hi = p.lig + 36 > 97 ? 97 : p.lig + 36;
        string memory rim = string.concat('fill="none" stroke="hsl(', hsl3(p.hue, p.sat, hi), ')" stroke-width="1.5" stroke-linejoin="round"');
        return string.concat(
            '<rect width="512" height="512" fill="url(#ox)" clip-path="url(#ca)" opacity="0.3"/>',
            '<polygon points="', fp, '" ', rim, "/>",
            '<polygon points="', tp, '" ', rim, "/>",
            '<circle cx="388" cy="300" r="12" ', rim, "/>",
            '<path d="M381 295h14M388 295v12" stroke="hsl(', hsl3(p.hue, p.sat, hi), ')" stroke-width="1.8"/>'
        );
    }

    /// @dev Transfer scars: hairline cracks starting at a vertex of the outline. Max 8.
    function scars(Pal memory p, Bar memory b, int256[V] memory xs, int256[V] memory ys)
        internal
        pure
        returns (string memory s)
    {
        uint256 n = b.scars > 8 ? 8 : b.scars;
        uint256 hi = p.lig + 40 > 98 ? 98 : p.lig + 40;
        for (uint256 k = 0; k < n; k++) {
            uint256 r = rnd(b.lattice, 9000 + k);
            uint256 v = r % V;
            int256 sx = (r >> 8) & 1 == 0 ? int256(1) : int256(-1);
            s = string.concat(
                s, '<path d="M', i(xs[v]), " ", i(ys[v]), "l", i(sx * int256(5 + (r >> 16) % 9)), " ", i(int256(3 + (r >> 24) % 8)),
                "l", i(-sx * int256(2 + (r >> 32) % 7)), " ", i(int256(3 + (r >> 40) % 8)),
                "l", i(sx * int256(3 + (r >> 48) % 7)), " ", i(int256(2 + (r >> 56) % 7)),
                '" fill="none" stroke="hsl(', hsl3(p.hue, p.sat, hi), ')" stroke-width="1" opacity="0.9"/>'
            );
        }
    }

    function sign(Bar memory b) internal pure returns (string memory) {
        return string.concat(
            '<text x="18" y="492" font-family="ui-monospace,Menlo,Consolas,monospace" font-size="11" letter-spacing="1" fill="#a7afbf" opacity="0.9">',
            "THE FORGE #", u(b.tokenId), unicode" · ", familyName(b.family), unicode" · ", formName(b.form),
            b.generation > 0 ? string.concat(unicode" · GEN ", u(b.generation)) : "",
            unicode" · ", u(b.strikes), " STRIKES", unicode" · H", u(b.hardness), "</text>"
        );
    }

    // ------------------------------------------------------------------ helpers
    function u(uint256 v) internal pure returns (string memory) {
        return LibString.toString(v);
    }

    function i(int256 v) internal pure returns (string memory) {
        return LibString.toString(v);
    }

    function hsl3(uint256 h, uint256 s, uint256 l) internal pure returns (string memory) {
        return string.concat(u(h), ",", u(s), "%,", u(l), "%");
    }

    /// @dev Two-digit decimal fraction: 7 -> "07", 45 -> "45", 100+ -> "99".
    function pad2(uint256 v) internal pure returns (string memory) {
        if (v >= 100) return "99";
        if (v < 10) return string.concat("0", u(v));
        return u(v);
    }

    function clampNoise(int256 v) internal pure returns (int256) {
        if (v > NOISE_CAP) return NOISE_CAP;
        if (v < -NOISE_CAP) return -NOISE_CAP;
        return v;
    }

    function clampPx(int256 v) internal pure returns (int256) {
        if (v < 8) return 8;
        if (v > 470) return 470;
        return v;
    }
}
