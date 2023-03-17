// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Struct {
    uint256 constant BOOL_MASK = 1;

    // Validity
    uint256 constant VALID = 0;
    uint256 constant ROYALTIES = 1;
    uint256 constant INACTIVE = 2;
    uint256 constant OTHER = 3; // USER?
    uint256 constant REDEEMED = 4;
    uint256 constant BURNED = 5;

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

    uint256 constant MAX_PERIOD = 63113852; //2 years

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
        uint256 votes;
        string sData;
    }

    struct TokenSData {
        uint256 tokenId; // Physical authentication id (tokenId mapping)
        string sData;
    }

    // _owners eXtended storage -> mutable data
    // uint256 constant MPOS_OWNER = 0; // 24 bits, max 16777215
    // uint256 constant MPOS_XFER_COUNTER = 160; // 24 bits, max 16777215
    // uint256 constant MPOS_VALIDITYSTAMP = 184; // 40 bits
    // uint256 constant MPOS_VALIDITY = 224; // 4 bits, max 15
    // uint256 constant MPOS_UPGRADED = 228; // 1 bit, max 1
    // uint256 constant MPOS_DISPLAY = 229; // 1 bit, max 1
    // uint256 constant MPOS_LOCKED = 230; // 1 bit, max 1
    // uint256 constant MPOS_INSURANCE = 231; // 20 bits, max 1048575
    // uint256 constant MPOS_VOTES = 251; // 5 bits, max 31

    uint256 constant MPOS_LOCKED = 0; // 1 bit, max 1
    uint256 constant MPOS_VALIDITY = 1; // 4 bits, max 15
    uint256 constant MPOS_VALIDITYSTAMP = 5; // 40 bits
    uint256 constant MPOS_UPGRADED = 45; // 1 bit, max 1
    uint256 constant MPOS_DISPLAY = 46; // 1 bit, max 1
    uint256 constant MPOS_INSURANCE = 47; // 20 bits, max 1048575
    uint256 constant MPOS_VOTES = 67; // 5 bits, max 31
    uint256 constant MPOS_OWNER = 72; // 160 bits
    uint256 constant MPOS_XFER_COUNTER = 232; // 24 bits, max 16777215

    // _uTokenData -> mostly immutable by code logic
    uint256 constant UPOS_GLOBAL_MINT_ID = 0; // 16 bits
    uint256 constant UPOS_MINTSTAMP = 16; // 40 bits
    uint256 constant UPOS_EDITION = 56; // 7 bits, max 127 (cannot be greater than 99 in logic)
    uint256 constant UPOS_EDITION_MINT_ID = 63; // 16 bits, max 65535
    uint256 constant UPOS_CNTRYTAG = 79; // 4 bits, max 15
    uint256 constant UPOS_CNTRYTUSH = 83; // 4 bits, max 15
    uint256 constant UPOS_GENTAG = 87; // 6 bits, max 63
    uint256 constant UPOS_GENTUSH = 93; // 6 bits, max 63
    uint256 constant UPOS_MARKERTUSH = 99; // 4 bits, max 15
    uint256 constant UPOS_SPECIAL = 103; // 4 bits, max 15
    uint256 constant UPOS_RARITYTIER = 107; // 4 bits, max 15
    uint256 constant UPOS_ROYALTY = 111; // 10 bits, max 1023 (MUTABLE)
    uint256 constant UPOS_ROYALTIES_DUE = 121; // 15 bits, max 32767 (MUTABLE)
    uint256 constant UPOS_RESERVED = 136; // 120 bits (MUTABLE)

    uint256 constant MSZ_VALIDITY = 4;
    uint256 constant MSZ_INSURANCE = 20;
    uint256 constant MSZ_VOTES = 5;

    uint256 constant USZ_EDITION = 7;
    uint256 constant USZ_CNTRYTAG = 4;
    uint256 constant USZ_CNTRYTUSH = 4;
    uint256 constant USZ_GENTAG = 6;
    uint256 constant USZ_GENTUSH = 6;
    uint256 constant USZ_MARKERTUSH = 4;
    uint256 constant USZ_SPECIAL = 4;
    uint256 constant USZ_RARITYTIER = 4;
    uint256 constant USZ_ROYALTY = 10;
    uint256 constant USZ_ROYALTIES_DUE = 15;

    uint256 constant MASK_VALIDITY = 2**MSZ_VALIDITY-1;
    uint256 constant IMASK_VALIDITY = 2**(256-MSZ_VALIDITY)-1;
    uint256 constant MASK_ROYALTY = 2**USZ_ROYALTY-1;
    uint256 constant MASK_ROYALTIES_DUE = 2**USZ_ROYALTIES_DUE-1;
    uint256 constant MASK_ADDRESS_XFER = 2**184-1;
    uint256 constant MASK_BALANCER = 2**64-1;



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