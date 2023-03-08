// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Struct {
    uint256 constant BOOL_MASK = 1;

    // Validity
    uint256 constant VALID = 0;
    uint256 constant ROYALTIES = 1;
    uint256 constant INACTIVE = 2;
    uint256 constant OTHER = 3;
    uint256 constant REDEEMED = 4;

    // Upgraded
    uint256 constant UPGRADED = 1;

    // Locked
    uint256 constant UNLOCKED = 0;
    uint256 constant LOCKED = 1;

    // Displays
    uint256 constant ONCHAIN_SVG = 0;
    uint256 constant EXTERNAL_IMG = 1;

    // URIs
    uint256 constant URI0 = 0;
    uint256 constant URI1 = 1;

    struct TokenData {
        uint256 upgraded;
        uint256 display;
        uint256 locked;
        uint256 validity; // Validity flag to show whether not token is redeemable
        uint256 edition; // Physical edition
        uint256 cntrytag; // Hang tag country id
        uint256 cntrytush; // Tush tag country id
        uint256 gentag; // Hang tag generation
        uint256 gentush; // Tush tag generation
        uint256 markertush; // Tush tag special marker id
        uint256 special; // Special id
        uint256 raritytier; // Rarity tier id
        uint256 mintid; // Mint id for the physical edition id
        uint256 royalty; // Royalty amount
        uint256 royaltiesdue;
        uint256 tokenid; // Physical authentication id (tokenId mapping)
        uint256 validitystamp; // Needed if validity invalid
        uint256 mintstamp; // Minting timestamp
        uint256 insurance; // Insured value
        string sData;
    }

    struct TokenSData {
        uint256 tokenId; // Physical authentication id (tokenId mapping)
        string sData;
    }

    // _owners eXtended storage -> immutable data set on mint
    uint256 constant XPOS_MINTSTAMP = 160; // 40 bits
    uint256 constant XPOS_EDITION = 200; // 8 bits, max 255
    uint256 constant XPOS_EDITION_MINT_ID = 208; // 16 bits, max 65535
    uint256 constant XPOS_CNTRYTAG = 224; // 4 bits, max 15
    uint256 constant XPOS_CNTRYTUSH = 228; // 4 bits, max 15
    uint256 constant XPOS_GENTAG = 232; // 6 bits, max 63
    uint256 constant XPOS_GENTUSH = 238; // 6 bits, max 63
    uint256 constant XPOS_MARKERTUSH = 244; // 4 bits, max 15
    uint256 constant XPOS_SPECIAL = 248; // 4 bits, max 15
    uint256 constant XPOS_RARITYTIER = 252; // 4 bits, max 15

    uint256 constant XSZ_CNTRYTAG = 4;
    uint256 constant XSZ_CNTRYTUSH = 4;
    uint256 constant XSZ_GENTAG = 6;
    uint256 constant XSZ_GENTUSH = 6;
    uint256 constant XSZ_MARKERTUSH = 4;
    uint256 constant XSZ_SPECIAL = 4;
    uint256 constant XSZ_RARITYTIER = 4;
    
    /* Additional serving for dynamic data
     * Less concerned about packing so we're sticking with 
     * easier to work types, 8 bit, 16 bit, etc.
     */
    uint256 constant DPOS_GLOBAL_MINT_ID = 0; // 24 bits, max 16777215 (also functions as _allTokenIndex in ERC721Enumerable)
    uint256 constant DPOS_VALIDITYSTAMP = 24; // 40 bits
    uint256 constant DPOS_VALIDITY = 64; // 4 bits, max 15
    uint256 constant DPOS_UPGRADED = 68; // 1 bit, max 1
    uint256 constant DPOS_DISPLAY = 69; // 1 bit, max 1
    uint256 constant DPOS_LOCKED = 70; // 1 bit, max 1
    uint256 constant DPOS_ROYALTY = 71; // 10 bits, max 1023
    uint256 constant DPOS_ROYALTIES_DUE = 81; // 16 bits, max 65535
    uint256 constant DPOS_INSURANCE = 97; // 23 bits, max 8388607
    uint256 constant DPOS_XFER_COUNTER = 120; // 24 bits, max 16777215
    uint256 constant DPOS_RESERVED = 144; // 112 bits extra storage (14 bools, 14 chars, etc.)

    uint256 constant DSZ_VALIDITY = 4;
    uint256 constant DSZ_ROYALTY = 10;
    uint256 constant DSZ_INSURANCE = 23;

    uint256 constant DMASK_VALIDITY = 2**DSZ_VALIDITY-1;
    uint256 constant DMASK_ROYALTY = 2**DSZ_ROYALTY-1;

    /*
     * @dev Returns the indices that split sTokenData into 
     * name, qrData, barCodeData.
     */
    function _getSliceIndices(string calldata _sTokenData)
        internal pure
        returns (uint256 _sliceIndex1, uint256 _sliceIndex2) {
            bytes memory _bData = bytes(_sTokenData);
            for (_sliceIndex1; _sliceIndex1<32;) {
                if (_bData[_sliceIndex1] == 0x3d) {
                    break;
                }
                unchecked {++_sliceIndex1;}
            }
            uint256 _bDataLen = _bData.length;
            _sliceIndex2 = _sliceIndex1 + 50;
            for (_sliceIndex2; _sliceIndex2<_bDataLen;) {
                if (_bData[_sliceIndex2] == 0x3d) {
                    break;
                }
                unchecked {++_sliceIndex2;}
            }
    }
}