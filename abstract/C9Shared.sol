// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Shared {
    bytes3[11] hex3;
    mapping(bytes3 => bytes10) hex3ToColor;
    constructor() {
        hex3[0] = "101";
        hex3ToColor["101"] = "ONYX      ";
        hex3[1] = "fc3";
        hex3ToColor["fc3"] = "GOLD      ";
        hex3[2] = "bbb";
        hex3ToColor["bbb"] = "SILVER    ";
        hex3[3] = "a74";
        hex3ToColor["a74"] = "BRONZE    ";
        hex3[4] = "cb8";
        hex3ToColor["cb8"] = "CARDBOARD ";
        hex3[5] = "eee";
        hex3ToColor["eee"] = "PAPER     ";
        hex3[6] = "c0f";
        hex3ToColor["c0f"] = "AMETHYST  "; // STOPPED EARLY
        hex3[7] = "c00";
        hex3ToColor["c00"] = "RUBY      "; // EMBROIDERED
        hex3[8] = "0a0";
        hex3ToColor["0a0"] = "EMERALD   "; // ODDITY
        hex3[9] = "0cf";
        hex3ToColor["0cf"] = "SAPPHIRE  "; // FINITE QTY
        hex3[10] = "fff";
        hex3ToColor["fff"] = "NEBULA    "; // PROTO
    }

    /*
     * @dev Used in SVG and Metadata contracts.
     */
    bytes16[10] rarityTiers = [bytes16("R0 UNIQUE       "),
        "R1 GHOST        ",
        "R2 LEGENDARY    ",
        "R3 HYPER RARE   ",
        "R4 ULTRA RARE   ",
        "R5 RARE         ",
        "R6 UNCOMMON     ",
        "R7 COMMON       ",
        "R8 FREQUENT     ",
        "R9 ABUNDANT     "
    ];

    bytes16[6] specialTiers = [bytes16("                "),
        "STOPPED EARLY   ",
        "EMBROIDERED     ",
        "ODDITY          ",
        "FINITE QTY      ",
        "PROTO           "
    ];

    /*
     * @dev Valid country/region flags.
     */
    bytes3[8] _vFlags = [
        bytes3("CAN"),
        "CHN",
        "GER",
        "IND",
        "KOR",
        "UK ",
        "US ",
        "UNQ"
    ];

    /*
     * @dev Tush tag special markers.
     */
    bytes4[4] _vMarkers = [
        bytes4("4L  "),
        "EMBS",
        "EMBF",
        "CE  "
    ];

    /*
     * @dev Token validity flags.
     */
    bytes16[5] _vValidity = [
        bytes16("REDEEMABLE      "),
        "ROYALTIES       ", //6 -> DEAD
        "INACTIVE        ", //7 -> DEAD
        "OTHER           ", //8 -> DEAD
        "REDEEMED        "
    ];

    function _getRarityTier(uint256 _genTag, uint256 _rarityTier, uint256 _specialTier)
        internal view
        returns(uint256, bytes16) {
            bytes16 _b16Tier = rarityTiers[_rarityTier];
            bytes memory _bTier = "                ";
            assembly {
                let dst := add(_bTier, 32)
                mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _b16Tier))
            }
            uint256 _bgIdx;
            if (_specialTier > 0) {
                bytes16 _sTier = specialTiers[_specialTier];
                _bTier[0] = _sTier[0];
                _bgIdx = _specialTier+5;
            }
            else {
                _bgIdx = _genTag;
            }
            return (_bgIdx, bytes16(_bTier));
    }
}