// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


abstract contract C9Shared {
    //425K mint cost with string, string, string
    //

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
        uint56 mintstamp; // Minting timestamp
        string name; // Name to display on SVG
        string qrdata; // QR data to display on SVG
        string bardata; // Bar code data to display on SVG
    }

    /*
     * @dev Valid country/region flags.
     */
    bytes3[8] _vFlags = [
        bytes3("CAN"),
        "CHN",
        "GER",
        "IND",
        "KOR",
        "UK",
        "US",
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
    bytes16[4] _vValidity = [
        bytes16("PRE-RELEASE     "),
        "ROYALTIES DUE   ",
        "TRANSFER DUE    ",
        "OTHER           "
    ];
}