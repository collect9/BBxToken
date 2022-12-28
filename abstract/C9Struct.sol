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
        uint256 tokenid; // Physical authentication id
        uint256 validitystamp; // Needed if validity invalid
        uint256 mintstamp; // Minting timestamp
        string sData;
    }

    uint256 constant POS_UPGRADED = 0;
    uint256 constant POS_DISPLAY = 1;
    uint256 constant POS_LOCKED = 2;
    uint256 constant POS_VALIDITY = 3;
    uint256 constant POS_EDITION = 11;
    uint256 constant POS_CNTRYTAG = 19;
    uint256 constant POS_CNTRYTUSH = 27;
    uint256 constant POS_GENTAG = 35;
    uint256 constant POS_GENTUSH = 43;
    uint256 constant POS_MARKERTUSH = 51;
    uint256 constant POS_SPECIAL = 59;
    uint256 constant POS_RARITYTIER = 67;
    uint256 constant POS_MINTID = 75;
    uint256 constant POS_ROYALTY = 91;
    uint256 constant POS_ROYALTIESDUE = 107;
    uint256 constant POS_TOKENID = 123;
    uint256 constant POS_VALIDITYSTAMP = 155;
    uint256 constant POS_MINTSTAMP = 195;
    uint256 constant POS_RESERVED = 235;

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