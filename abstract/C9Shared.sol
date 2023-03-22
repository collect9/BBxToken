// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Shared {

    function _getHex3(uint256 colorId)
    internal pure
    returns (bytes32) {
        bytes32 _hex3 = "101fc3bbba74cb8eeec0fc000a00cfff";
        return _hex3<<(colorId*3*8);
    }

    function _getColorText(uint256 colorId)
    internal pure
    returns (bytes10) {
        bytes10[11] memory _colors = [bytes10("ONYX      "),
            "GOLD      ",
            "SILVER    ",
            "BRONZE    ",
            "CARDBOARD ",
            "PAPER     ",
            "AMETHYST  ",
            "RUBY      ",
            "EMERALD   ",
            "SAPPHIRE  ",
            "NEBULA    "
        ];
        return _colors[colorId];
    }

    function _getFlagText(uint256 flagId)
    internal pure
    returns (bytes32) {
        bytes32 _vFlags = "CANCHNGERINDKORUK US UNQ      ";
        return _vFlags<<(flagId*3*8);
    }


    function _getMarkerText(uint256 markerId)
    internal pure
    returns (bytes32) {
        bytes32 _vMarkers = "    4L  EMBSEMBFCE  ks  Bs      ";
        return _vMarkers<<(markerId*4*8);
    }

    /*
     * @dev Token validity flags.
     */
    function _getValidityText(uint256 vId)
    internal pure
    returns (bytes16) {
        bytes16[5] memory _vValidity = [
            bytes16("REDEEMABLE      "),
            "ROYALTIES       ", //6 -> DEAD
            "INACTIVE        ", //7 -> DEAD
            "OTHER           ", //8 -> DEAD
            "REDEEMED        "  //9 -> BURNED
        ];
        return _vValidity[vId];
    }

    /*
     * @dev. Sionce the rarityTiers and specialTiers are not used in another
     * contracts, they are hardcoded into the byte code to save on gas 
     * costs.
     */
    function _getRarityTier(uint256 _genTag, uint256 _rarityTier, uint256 _specialTier)
        internal pure
        returns(uint256, bytes16) {

            bytes16[10] memory _rarityTiers = [bytes16("R0 UNIQUE       "),
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

            bytes16[6] memory _specialTiers = [bytes16("REGULAR         "),
                "STOPPED EARLY   ",
                "EMBROIDERED     ",
                "ODDITY          ",
                "FINITE QTY      ",
                "PROTO           "
            ];

            bytes16 _b16Tier = _rarityTiers[_rarityTier];
            bytes memory _bTier = "                ";
            assembly {
                let dst := add(_bTier, 32)
                mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _b16Tier))
            }
            uint256 _bgIdx;
            if (_specialTier > 0) {
                bytes16 _sTier = _specialTiers[_specialTier];
                _bTier[0] = _sTier[0];
                unchecked {_bgIdx = _specialTier+5;}
            }
            else {
                _bgIdx = _genTag;
            }
            return (_bgIdx, bytes16(_bTier));
    }
}