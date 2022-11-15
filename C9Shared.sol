// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;

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
        hex3[4] = "c0f";
        hex3ToColor["c0f"] = "AMETHYST  ";
        hex3[5] = "c00";
        hex3ToColor["c00"] = "RUBY      ";
        hex3[6] = "0a0";
        hex3ToColor["0a0"] = "EMERALD   ";
        hex3[7] = "0cf";
        hex3ToColor["0cf"] = "SAPPHIRE  ";
        hex3[8] = "eee";
        hex3ToColor["eee"] = "DIAMOND   ";
        hex3[9] = "cb8";
        hex3ToColor["cb8"] = "CARDBOARD ";
        hex3[10] = "fff";
        hex3ToColor["fff"] = "NEBULA    ";
    }

    struct TokenInfo {
        uint8 validity; // Validity flag to show whether not token is redeemable
        uint8 edition; // Physical edition
        uint8 tag; // Hang tag country id
        uint8 tush; // Tush tag country id
        uint8 gentag; // Hang tag generation
        uint8 gentush; // Tush tag generation
        uint8 markertush; // Tush tag special marker id
        uint8 spec; // Special id
        uint8 rtier; // Rarity tier id
        uint16 mintid; // Mint id for the physical edition id
        uint16 royalty; // Royalty amount
        uint32 id; // Physical authentication id
        uint48 mintstamp; // Minting timestamp
        string name; // Name to display on SVG -> not worth storing as bytes32
        string qrdata; // QR data to display on SVG
        string bardata; // Bar code data to display on SVG
    }

    /*
     * @dev Used in SVG and Metadata contracts.
     */
    bytes16[12] rtiers = [bytes16("T0 GHOST        "),
        "T1 LEGENDARY    ",
        "T2 HYPER RARE   ",
        "T3 ULTRA RARE   ",
        "T4 RARE         ",
        "T5 UNCOMMON     ",
        "T6 COMMON       ",
        "T7 ABUNDANT     ",
        "S0 PROTO UNIQUE ",
        "S1 ODDITY RARE  ",
        "S2 PROD HALT    ",
        "S3 FINITE QTY   "
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
        "ROYALTIES DUE   ",
        "INACTIVE        ",
        "OTHER           ",
        "REDEEMED        "
    ];
}