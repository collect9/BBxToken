// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Struct {
    // For readability
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

    // Period constants
    uint256 constant MAX_PERIOD = 63113852; //2 years

    // Token mint data struct
    struct TokenData {
        string name; // Name
        uint256 upgraded; // Token upgraded bool
        uint256 display; // Display type bool
        uint256 locked; // Token lock bool
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
        uint256 votes; // Number of votes the token is worth
        uint256 cData; // Binary mapped QR code and barcode data
    }

    // Packed positions within ownerData - everything is mutable except votes
    uint256 constant MPOS_LOCKED = 0; // 1 bit, max 1
    uint256 constant MPOS_VALIDITY = 1; // 4 bits, max 15
    uint256 constant MPOS_VALIDITYSTAMP = 5; // 38 bits
    uint256 constant MPOS_UPGRADED = 43; // 1 bit, max 1
    uint256 constant MPOS_DISPLAY = 44; // 1 bit, max 1
    uint256 constant MPOS_INSURANCE = 45; // 20 bits, max 1048575
    uint256 constant MPOS_ROYALTY = 65; // 7 bits, max 127 (multi by 10)
    uint256 constant MPOS_VOTES = 72; // 4 bits, max 15 (IMMUTABLE by code logic)
    uint256 constant MPOS_OWNER = 76; // 160 bits
    uint256 constant MPOS_XFER_COUNTER = 236; // 20 bits, max 1048575

    // Sizes of packed data in ownerData
    uint256 constant MSZ_VALIDITY = 4;
    uint256 constant MSZ_INSURANCE = 20;
    uint256 constant MSZ_ROYALTY = 7;
    uint256 constant MSZ_VOTES = 4;
    uint256 constant MSZ_XFER_COUNTER = 20;

    // Masks of packed data in ownerData
    uint256 constant M_MASK_VALIDITY = 2**MSZ_VALIDITY-1;
    uint256 constant M_MASK_ROYALTY = 2**MSZ_ROYALTY-1;
    uint256 constant M_IMASK_VALIDITY = 2**(256-MSZ_VALIDITY)-1;

    // Packed positions within uTokenData - everything is immutable except royalties due
    uint256 constant UPOS_MINTSTAMP = 0; // 40 bits
    uint256 constant UPOS_EDITION = 38; // 7 bits, max 127 (cannot be greater than 99 in logic)
    uint256 constant UPOS_EDITION_MINT_ID = 45; // 15 bits, max 32767
    uint256 constant UPOS_CNTRYTAG = 60; // 4 bits, max 15
    uint256 constant UPOS_CNTRYTUSH = 64; // 4 bits, max 15
    uint256 constant UPOS_GENTAG = 68; // 5 bits, max 31
    uint256 constant UPOS_GENTUSH = 73; // 5 bits, max 31
    uint256 constant UPOS_MARKERTUSH = 78; // 4 bits, max 15
    uint256 constant UPOS_SPECIAL = 82; // 4 bits, max 15
    uint256 constant UPOS_RARITYTIER = 86; // 4 bits, max 15
    uint256 constant UPOS_ROYALTIES_DUE = 90; // 14 bits, max 16383 (MUTABLE by code logic)
    uint256 constant UPOS_NAME = 104; //152 bits, 19 characters max name length

    // Sizes of packed data in uTokenData
    uint256 constant USZ_EDITION = 7;
    uint256 constant USZ_EDITION_MINT_ID = 15;
    uint256 constant USZ_CNTRYTAG = 4;
    uint256 constant USZ_CNTRYTUSH = 4;
    uint256 constant USZ_GENTAG = 5;
    uint256 constant USZ_GENTUSH = 5;
    uint256 constant USZ_MARKERTUSH = 4;
    uint256 constant USZ_TIMESTAMP = 38;
    uint256 constant USZ_SPECIAL = 4;
    uint256 constant USZ_RARITYTIER = 4;
    uint256 constant USZ_ROYALTIES_DUE = 14;
    uint256 constant USZ_NAME = 152;

    // Masks of packed data in uTokenData
    uint256 constant U_MASK_ROYALTIES_DUE = 2**USZ_ROYALTIES_DUE-1;
    
    // Masks of packed data in balances
    uint256 constant MASK_ADDRESS_XFER = 2**184-1;
    uint256 constant MASK_BALANCER = 2**64-1;
}