// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "solady/tokens/ERC721.sol";
import {ERC2981} from "solady/tokens/ERC2981.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {ForgeArt} from "./ForgeArt.sol";
import {ForgeRenderer} from "./ForgeRenderer.sol";

/// @title THE FORGE / FORGE
/// @notice Fully on-chain, dynamic, ownerless-after-setup collection on Base.
///
///  Every token is a bar of raw metal. Strike it and the outline changes forever.
///  Strike it `temperAt` times and it tempers: shape locked, immune to cooling.
///  Fuse two shaped bars and both burn to mint one rarer alloy. Leave a shaped bar
///  longer than `coolAfter` and anyone may call `temper()` to cool it: it loses
///  hardness and one strike, and can fall back to raw.
///
///  Inherited from LIVING SEEDS (tested skeleton): tranche pricing, per-wallet cap,
///  ERC-2981 royalties, 70/30 fee split via `harvest()`, transfer scars,
///  ERC-4906 metadata refresh, `currentPrice()` for agents that read before paying.
///
///  Marketplace visibility: `tokenURI` and `contractURI` are data URIs with the
///  SVG embedded, so OpenSea, Rarible, Magic Eden, Zora and any ERC-721 indexer
///  render the art with no server and no IPFS.
contract TheForge is ERC721, ERC2981, Ownable {
    using LibString for uint256;

    // ------------------------------------------------------------------ errors
    error Price();
    error SoldOut();
    error ReserveEmpty();
    error BadPayment();
    error NotOwner();
    error TooMany();
    error NothingToHarvest();
    error Locked(); // tempered bars cannot be struck
    error TooSoon(); // one strike per bar per STRIKE_COOLDOWN
    error RawCannotFuse();
    error SameBar();

    // ------------------------------------------------------------------ events
    event Cast(uint256 indexed id, address indexed smith, uint256 lattice, uint8 family);
    event Struck(uint256 indexed id, address indexed smith, uint32 strikes, uint16 hardness);
    event Tempered(uint256 indexed id, uint16 hardness);
    event Fused(uint256 indexed id, uint256 indexed a, uint256 indexed b, uint8 family, uint8 generation);
    event Cooled(uint256 indexed id, uint32 strikes, uint16 hardness, uint8 form);
    event Quenched(uint256 indexed id);
    event Harvested(uint256 primaryAmt, uint256 secondaryAmt);
    /// @dev EIP-4906
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    // ------------------------------------------------------------------ constants
    uint256 public constant MAX_SUPPLY = 333; // cast bars; alloys do not count
    uint256 public constant ARTIST_RESERVE = 8;
    uint256 public constant T0_END = 33;
    uint256 public constant T1_END = 133;
    uint256 public constant T2_END = 233;
    uint256 public constant T0_PRICE = 0.003 ether;
    uint256 public constant T1_PRICE = 0.005 ether;
    uint256 public constant T2_PRICE = 0.008 ether;
    uint256 public constant T3_PRICE = 0.012 ether;
    uint256 public constant STRIKE_COOLDOWN = 10 minutes;
    uint256 public constant TEMPER_BATCH = 50; // bars inspected per temper() call
    uint16 public constant MAX_HARDNESS = 1000;
    uint16 public constant STRIKE_HARDNESS = 10;
    uint16 public constant COOL_HARDNESS = 20;
    uint16 public constant FUSE_BONUS = 50;

    // ------------------------------------------------------------------ immutables
    address payable public immutable primaryTreasury;
    address payable public immutable secondaryTreasury;
    uint256 public immutable secondaryBps; // share of harvested balance to secondary, bp
    uint256 public immutable strikeFee;
    uint256 public immutable fuseFee;
    uint256 public immutable maxPerWallet;
    uint32 public immutable temperAt; // strikes needed to temper
    uint64 public immutable coolAfter; // seconds of neglect before cooling applies
    ForgeRenderer public immutable renderer; // the artist, fixed forever

    // ------------------------------------------------------------------ state
    struct Bar {
        uint128 lattice; // crystal seed, fixed at cast or fuse
        uint64 lastHeat; // last strike / fuse / quench / cool
        uint32 strikes;
        uint16 hardness; // 0..1000
        uint16 scars; // transfers
        uint8 family; // 0 iron 1 copper 2 silver 3 gold 4 meteor 5 damascus
        uint8 form; // 0 raw 1 shaped 2 tempered
        uint8 generation; // 0 cast, n fused n times
        uint32 parentA;
        uint32 parentB;
    }

    mapping(uint256 => Bar) public bars;
    uint256 public cast; // bars minted from the furnace (<= MAX_SUPPLY)
    uint256 public nextId; // next token id, alloys continue after cast ids
    uint256 public totalSupply; // living tokens
    uint256 public reserveMinted;
    uint256 public temperCursor;
    mapping(address => uint256) public mintedBy;

    constructor(
        address payable _primaryTreasury,
        address payable _secondaryTreasury,
        uint256 _royaltyBps, // 500 = 5%
        uint256 _secondaryBps, // 3000 = 30%
        uint256 _strikeFee, // 0.0003 ether
        uint256 _fuseFee, // 0.002 ether
        uint256 _maxPerWallet, // 5
        uint32 _temperAt, // 21
        uint64 _coolAfter, // 3 days
        ForgeRenderer _renderer
    ) {
        renderer = _renderer;
        _initializeOwner(msg.sender);
        primaryTreasury = _primaryTreasury;
        secondaryTreasury = _secondaryTreasury;
        secondaryBps = _secondaryBps;
        strikeFee = _strikeFee;
        fuseFee = _fuseFee;
        maxPerWallet = _maxPerWallet;
        temperAt = _temperAt;
        coolAfter = _coolAfter;
        _setDefaultRoyalty(_primaryTreasury, uint96(_royaltyBps));
    }

    // ------------------------------------------------------------------ identity
    function name() public pure override returns (string memory) {
        return "THE FORGE";
    }

    function symbol() public pure override returns (string memory) {
        return "FORGE";
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return interfaceId == 0x49064906 || ERC721.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // ------------------------------------------------------------------ pricing
    function priceFor(uint256 cast_) public pure returns (uint256) {
        if (cast_ < T0_END) return T0_PRICE;
        if (cast_ < T1_END) return T1_PRICE;
        if (cast_ < T2_END) return T2_PRICE;
        return T3_PRICE;
    }

    /// @notice Exact msg.value `mint()` expects right now. Agents read this first.
    function currentPrice() public view returns (uint256) {
        return priceFor(cast);
    }

    function quenchFee() public view returns (uint256) {
        return strikeFee * 3;
    }

    // ------------------------------------------------------------------ mint
    /// @notice Cast a raw bar at the current tranche price. Per-wallet cap applies.
    function mint() external payable returns (uint256 id) {
        if (msg.value != currentPrice()) revert Price();
        if (mintedBy[msg.sender] >= maxPerWallet) revert TooMany();
        mintedBy[msg.sender]++;
        id = _cast(msg.sender);
    }

    /// @notice Artist reserve: up to ARTIST_RESERVE bars, no price, owner only.
    function mintFor(address to) external onlyOwner returns (uint256 id) {
        if (reserveMinted >= ARTIST_RESERVE) revert ReserveEmpty();
        reserveMinted++;
        id = _cast(to);
    }

    function _cast(address to) internal returns (uint256 id) {
        if (cast >= MAX_SUPPLY) revert SoldOut();
        cast++;
        id = nextId++;
        uint256 h = uint256(blockhash(block.number - 1));
        uint256 g = uint256(keccak256(abi.encodePacked(h, block.timestamp, tx.origin, msg.sender, id)));
        uint8 fam = familyFromLattice(g);
        bars[id] = Bar({
            lattice: uint128(g),
            lastHeat: uint64(block.timestamp),
            strikes: 0,
            hardness: 0,
            scars: 0,
            family: fam,
            form: 0,
            generation: 0,
            parentA: 0,
            parentB: 0
        });
        totalSupply++;
        _mint(to, id);
        emit Cast(id, to, g, fam);
    }

    /// @dev iron 50% · copper 25% · silver 15% · gold 8% · meteor 2%
    function familyFromLattice(uint256 g) public pure returns (uint8) {
        uint256 r = g % 100;
        if (r < 50) return 0;
        if (r < 75) return 1;
        if (r < 90) return 2;
        if (r < 98) return 3;
        return 4;
    }

    // ------------------------------------------------------------------ strike
    /// @notice One hammer blow. Changes the outline forever, raises hardness, reheats.
    ///         At `temperAt` strikes the bar tempers and locks.
    function strike(uint256 id) external payable {
        if (msg.sender != ownerOf(id)) revert NotOwner();
        if (msg.value != strikeFee) revert Price();
        Bar storage b = bars[id];
        if (b.form == 2) revert Locked();
        if (b.strikes > 0 && block.timestamp < uint256(b.lastHeat) + STRIKE_COOLDOWN) revert TooSoon();

        b.strikes++;
        uint16 h = b.hardness + STRIKE_HARDNESS;
        b.hardness = h > MAX_HARDNESS ? MAX_HARDNESS : h;
        b.lastHeat = uint64(block.timestamp);
        if (b.form == 0) b.form = 1;
        emit Struck(id, msg.sender, b.strikes, b.hardness);

        if (b.strikes >= temperAt) {
            b.form = 2;
            emit Tempered(id, b.hardness);
        }
        emit MetadataUpdate(id);
    }

    // ------------------------------------------------------------------ fuse
    /// @notice Burn two shaped or tempered bars you own; mint one alloy.
    ///         Same family stays; mixed families become damascus. Alloys are immune
    ///         to cooling and carry the greater hardness plus a bonus.
    function fuse(uint256 a, uint256 b_) external payable returns (uint256 id) {
        if (a == b_) revert SameBar();
        if (msg.sender != ownerOf(a) || msg.sender != ownerOf(b_)) revert NotOwner();
        if (msg.value != fuseFee) revert Price();
        Bar memory A = bars[a];
        Bar memory B = bars[b_];
        if (A.form == 0 || B.form == 0) revert RawCannotFuse();

        _burn(a);
        _burn(b_);
        delete bars[a];
        delete bars[b_];
        totalSupply -= 2;

        id = nextId++;
        uint256 g = uint256(keccak256(abi.encodePacked(uint256(A.lattice), uint256(B.lattice), id)));
        uint8 fam = A.family == B.family ? A.family : 5;
        uint16 h = (A.hardness > B.hardness ? A.hardness : B.hardness) + FUSE_BONUS;
        uint8 gen = (A.generation > B.generation ? A.generation : B.generation);
        if (gen < 255) gen++;
        bars[id] = Bar({
            lattice: uint128(g),
            lastHeat: uint64(block.timestamp),
            strikes: 0,
            hardness: h > MAX_HARDNESS ? MAX_HARDNESS : h,
            scars: 0,
            family: fam,
            form: 1,
            generation: gen,
            parentA: uint32(a),
            parentB: uint32(b_)
        });
        totalSupply++;
        _mint(msg.sender, id);
        emit Fused(id, a, b_, fam, gen);
    }

    // ------------------------------------------------------------------ temper (cooling)
    /// @notice Cool neglected bars. Anyone may call; a daily cron is enough.
    ///         Inspects at most TEMPER_BATCH ids from a rotating cursor, so gas is bounded.
    ///         Tempered bars and alloys are immune.
    function temper() external returns (uint256 cooled) {
        uint256 n = nextId;
        if (n == 0) return 0;
        uint256 start = temperCursor;
        uint256 lo = type(uint256).max;
        uint256 hi = 0;
        for (uint256 k = 0; k < TEMPER_BATCH && k < n; k++) {
            uint256 id = (start + k) % n;
            if (_cool(id)) {
                cooled++;
                if (id < lo) lo = id;
                if (id > hi) hi = id;
            }
        }
        temperCursor = (start + (TEMPER_BATCH < n ? TEMPER_BATCH : n)) % n;
        if (cooled > 0) emit BatchMetadataUpdate(lo, hi);
    }

    function _cool(uint256 id) internal returns (bool) {
        if (!_exists(id)) return false;
        Bar storage b = bars[id];
        if (b.form != 1 || b.generation != 0) return false;
        if (block.timestamp < uint256(b.lastHeat) + coolAfter) return false;
        b.hardness = b.hardness > COOL_HARDNESS ? b.hardness - COOL_HARDNESS : 0;
        if (b.strikes > 0) b.strikes--;
        if (b.strikes == 0) b.form = 0;
        b.lastHeat = uint64(block.timestamp);
        emit Cooled(id, b.strikes, b.hardness, b.form);
        return true;
    }

    /// @notice Whether a bar would cool if `temper()` ran now.
    function isCold(uint256 id) public view returns (bool) {
        Bar memory b = bars[id];
        return b.form == 1 && b.generation == 0 && block.timestamp >= uint256(b.lastHeat) + coolAfter;
    }

    /// @notice 100 just after heat, 0 when `coolAfter` has passed. Drives the glow.
    function heatOf(uint256 id) public view returns (uint8) {
        uint256 e = block.timestamp - bars[id].lastHeat;
        if (e >= coolAfter) return 0;
        return uint8(100 - (e * 100) / coolAfter);
    }

    // ------------------------------------------------------------------ quench
    /// @notice Reheat without striking: protects a bar you cannot work this week. 3x strike fee.
    function quench(uint256 id) external payable {
        if (msg.sender != ownerOf(id)) revert NotOwner();
        if (msg.value != quenchFee()) revert Price();
        bars[id].lastHeat = uint64(block.timestamp);
        emit Quenched(id);
        emit MetadataUpdate(id);
    }

    // ------------------------------------------------------------------ art
    function tokenSVG(uint256 id) public view returns (string memory) {
        Bar memory b = bars[id];
        return renderer.render(_art(id, b));
    }

    function _art(uint256 id, Bar memory b) internal view returns (ForgeArt.Bar memory) {
        return ForgeArt.Bar({
            lattice: uint256(b.lattice),
            family: b.family,
            form: b.form,
            strikes: b.strikes,
            hardness: b.hardness,
            heat: heatOf(id),
            scars: b.scars,
            generation: b.generation,
            tokenId: id
        });
    }

    function familyName(uint8 f) public view returns (string memory) {
        return renderer.familyName(f);
    }

    function formName(uint8 f) public view returns (string memory) {
        return renderer.formName(f);
    }

    /// @notice Fully on-chain metadata: base64 JSON with the SVG embedded.
    function tokenURI(uint256 id) public view override returns (string memory) {
        ownerOf(id);
        Bar memory b = bars[id];
        string memory svg = renderer.render(_art(id, b));
        string memory json = string.concat(
            '{"name":"THE FORGE #', id.toString(),
            '","description":"A bar of metal that remembers every blow. Strike it and the outline changes forever. '
            'Strike it enough and it tempers. Fuse two and both burn to make one alloy. Neglect it and it cools. '
            'Rendered live from contract state: no server, no IPFS, no artist, only the hammer.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
            '","attributes":[', _attributes(id, b), "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _attributes(uint256 id, Bar memory b) internal view returns (string memory) {
        return string.concat(
            attr("Family", renderer.familyName(b.family)), ",",
            attr("Form", renderer.formName(b.form)), ",",
            attrNum("Strikes", b.strikes), ",",
            attrNum("Hardness", b.hardness), ",",
            attrNum("Generation", b.generation), ",",
            attrNum("Scars", b.scars), ",",
            attrNum("Heat", heatOf(id)), ",",
            attr("Lineage", b.generation == 0 ? "cast" : string.concat("#", uint256(b.parentA).toString(), " + #", uint256(b.parentB).toString())), ",",
            attr("Lattice", LibString.toHexString(uint256(b.lattice), 16))
        );
    }

    /// @notice ERC-7572 collection metadata for marketplaces. Image is an on-chain tempered gold bar.
    function contractURI() public view returns (string memory) {
        string memory svg = renderer.render(ForgeArt.Bar({
            lattice: uint256(keccak256("THE FORGE")),
            family: 3,
            form: 2,
            strikes: 21,
            hardness: 210,
            heat: 0,
            scars: 0,
            generation: 0,
            tokenId: 0
        }));
        string memory json = string.concat(
            '{"name":"THE FORGE","symbol":"FORGE","description":"333 bars of metal, fully on-chain on Base. '
            'Strike to shape, temper to lock, fuse to alloy, neglect to cool. No artist, only the hammer.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
            '","external_link":"https://3esign.github.io/the-forge/","collaborators":[]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ------------------------------------------------------------------ money
    /// @notice Split the balance: secondaryBps to secondary treasury, rest to primary. Anyone may call.
    function harvest() external {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToHarvest();
        uint256 secondary = (amount * secondaryBps) / 10000;
        uint256 primary = amount - secondary;
        if (secondary > 0) {
            (bool ok2,) = secondaryTreasury.call{value: secondary}("");
            if (!ok2) revert BadPayment();
        }
        (bool ok1,) = primaryTreasury.call{value: primary}("");
        if (!ok1) revert BadPayment();
        emit Harvested(primary, secondary);
    }

    // ------------------------------------------------------------------ scars
    function _afterTokenTransfer(address from, address to, uint256 id) internal override {
        if (from != address(0) && to != address(0)) {
            bars[id].scars++;
            emit MetadataUpdate(id);
        }
    }

    // ------------------------------------------------------------------ helpers
    function attr(string memory k, string memory v) internal pure returns (string memory) {
        return string.concat('{"trait_type":"', k, '","value":"', v, '"}');
    }

    function attrNum(string memory k, uint256 v) internal pure returns (string memory) {
        return string.concat('{"trait_type":"', k, '","value":', v.toString(), "}");
    }
}
