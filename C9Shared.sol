// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


abstract contract C9Shared {
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
        uint24 id; // Physical authentication id
        uint48 mintstamp; // Minting timestamp
        uint96 royalty; // Royalty amount
        string name; // Name to display on SVG
        string qrdata; // QR data to display on SVG
        string bardata; // Bar code data to display on SVG
    }

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

    bytes4[4] _vMarkers = [
        bytes4("4L  "),
        "EMBS",
        "EMBF",
        "CE  "
    ];
    
    bytes16[4] _vValidity = [
        bytes16("PRE-RELEASE     "),
        "ROYALTIES DUE   ",
        "TRANSFER DUE    ",
        "OTHER           "
    ];

    /**
     * @dev Necessary getters for array lengths.
     */
    /*
    function flagsLength()
        public view
        returns(uint256) {
            return _vFlags.length;
    }

    function markersLength()
        public view
        returns(uint256) {
            return _vMarkers.length;
    }

    function validityLength()
        public view
        returns(uint256) {
            return _vValidity.length;
    }
    */
}