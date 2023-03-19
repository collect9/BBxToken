// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Shared.sol";
import "./interfaces/IC9Token.sol";
import "./utils/C9Context.sol";
import "./utils/Helpers.sol";

import "./svg/C9Logo.sol";
import "./svg/C9Flags.sol";

contract C9SVG is C9Context, C9Shared {

    bytes constant QR_CODE_BASE = ""
        "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' class='c9QRcode' width='100%' height='100%' viewBox='0 0 17 17'>"
        "<style type='text/css'>"
            ".c9QRcode{opacity:0.89;} "
            ".c9QRcode rect{width:1px;height:1px;}"
        "</style>"
        "<rect x='0.5' y='0.5' style='width:6px;height:6px;stroke:#000;fill-opacity:0;'/>"
        "<rect x='2' y='2' style='width:3px;height:3px;'/>"
        "<rect x='15' y='4' style='height:7px;'/>"
        "<rect x='8'/>"
        "<rect x='10'/>"
        "<rect x='12'/>"
        "<rect x='14'/>"
        "<rect x='16'/>"
        "<rect y='8'/>"
        "<rect y='10'/>"
        "<rect y='12'/>"
        "<rect y='14'/>"
        "<rect y='16'/>"
        "<rect x='16' y='1'/>"
        "<rect x='9' y='2'/>"
        "<rect x='10' y='2'/>"
        "<rect x='13' y='3'/>"
        "<rect x='9' y='4'/>"
        "<rect x='11' y='4'/>"
        "<rect x='12' y='4'/>"
        "<rect x='13' y='5'/>"
        "<rect x='9' y='6'/>"
        "<rect x='11' y='7'/>"
        "<rect x='16' y='7'/>"
        "<rect x='2' y='8'/>"
        "<rect x='5' y='8'/>"
        "<rect x='7' y='8'/>"
        "<rect x='9' y='8'/>"
        "<rect x='10' y='8'/>"
        "<rect x='12' y='8'/>"
        "<rect x='16' y='8'/>"
        "<rect x='13' y='11'/>"
        "<rect x='14' y='11'/>"
        "<rect x='11' y='12'/>"
        "<rect x='12' y='12'/>"
        "<rect x='16' y='12'/>"
        "<rect x='16' y='13'/>"
        "<rect x='15' y='14'/>"
        "<rect x='11' y='15'/>"
        "<rect x='11' y='16'/>"
        "<rect x='12' y='16'/>";

    bytes constant BAR_CODE_BASE = ""
        "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' class='c9BARcode' width='100%' height='100%' viewBox='30 0 270 100'>"
        "<style type='text/css'>"
            ".c9BARcode{opacity:0.89;} "
            ".c9BARcode rect{height:1px;}"
        "</style>"
        "<g transform='scale(3 100)'>"
            "<rect x='10' width='1'/>"
            "<rect x='11' width='1'/>"
            "<rect x='13' width='1'/>"
            "<rect x='21' width='1'/>";

    bytes constant SVG_OPENER = ""
        "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' class='c9Tsvg' width='100%' height='100%' viewBox='0 0 630 880'>"
        "<style type='text/css'>"
            ".c9Tsvg{font-family:'Courier New';} "
            ".c9Tsvg rect{height:100%;} "
            ".c9Ts{font-size:22px;} "
            ".c9Tm{font-size:34px;} "
            ".c9Tl{font-size:54px;} "
            ".c9Tb{font-weight:700;}"
        "</style>"
        "<defs>"
            "<radialGradient id='rgXXXXXX' cx='50%' cy='44%' r='50%' gradientUnits='userSpaceOnUse'>"
                "<stop offset='0' stop-color='#fff'/>"
                "<stop offset='1' stop-color='#101'/>"
            "</radialGradient>"
            "<filter id='c9Nse'>"
                "<feTurbulence type='turbulence' baseFrequency='0.002' numOctaves='8'/>"
                "<feComposite in2='SourceGraphic' operator='in'/>"
                "<feColorMatrix values='1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 .0 .0 .0 .2 0'/>"
            "</filter>"
            "<filter id='c9Gs'>"
                "<feColorMatrix type='saturate' values='1.0'/>"
            "</filter>"
        "</defs>"
        "<g filter='url(#c9Gs)'>"
            "<rect width='100%' rx='20' fill='url(#rgXXXXXX)'/>"
            "<rect width='100%' rx='20' filter='url(#c9Nse)'/>"
            "<g transform='translate(20 20)' style='fill:#ded;'>"
                "<rect style='width:590px;height:150px;' rx='10'/>"
                "<rect y='720' style='width:590px;height:120px;' rx='10'/>"
            "</g>"
            "<rect y='560' style='width:100%;height:22px;fill:#ddf;fill-opacity:0.6;'/>"
            "<g transform='translate(30 58)' class='c9Tm'>"
                "<text>COLLECT9 PHYSICALLY</text>"
                "<text y='34'>REDEEMABLE NFT</text>"
                "<g class='c9Ts'>"
                    "<text y='74'>STATUS: <tspan class='c9Tb' fill='#080'>  VALID                    </tspan></text>"
                    "<text y='100'>EIP-2981: 3.50%</text>"
                    "<text y='710'>CLASS: VINTAGE BEANIE BABY</text>"
                    "<text y='736'>RARITY TIER:                                 </text>"
                    "<text y='762'>ED NUM.MINT ID:   .    </text>"
                    "<text y='788'>NFT AGE:   YR   MO   D</text>"
                "</g>"
            "</g>"
            "<g transform='translate(315 576)' text-anchor='middle'>"
                "<text fill='#999'>                                        </text>"
                "<text y='69' class='c9Tm c9Tb'>        |        </text>"
                "<text y='122' class='c9Tl c9Tb'>";

    address public immutable contractToken;
    address private contractFlags;
    address private contractLogo;

    constructor (address _contractFlags, address _contractLogo, address _contractToken) {
        contractToken = _contractToken;
        contractFlags = _contractFlags;
        contractLogo = _contractLogo;
    }

       /**
     * @dev Adds the bytes32 + bytes8 representation of the address into the 
     * SVG output memory.
     */
    function addAddress(address _address, bytes memory b)
    private pure {
        (bytes32 _a1, bytes8 _a2) = Helpers.addressToB32B8(_address);
        assembly {
            mstore(add(b, 1708), _a1)
            let dst := add(b, 1740)
            mstore(dst, or(and(mload(dst), not(shl(192, 0xFFFFFFFFFFFFFFFF))), _a2))
        }
    }

    /**
     * @dev Adds the `_id` into the SVG output memory `b`. 
     * Note: this is done so that multiple 
     * SVGs may be displayed on the same page without CSS conflict.
     */
    function addIds(bytes6 b6TokenId, bytes memory b)
    private pure {
        assembly {
            let dst := add(b, 364)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
            dst := add(b, 875)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
        }
    }

    // /**
    //  * @dev Adds validity flag info to SVG output memory `b`.
    //  */
    function addValidityInfo(uint256 tokenId, uint256 ownerData, bytes memory b)
    private view {
        uint256 _validityIdx = _currentVId(ownerData);

        bytes3 color;
        bytes16 validityText = _vValidity[_validityIdx % 5];
        uint256 _locked;
        if (_validityIdx == VALID) {
            bool _preRedeemable = IC9Token(contractToken).preRedeemable(tokenId);
            if (_preRedeemable) {
                color = "a0f"; // purple
                validityText = "PRE-REDEEMABLE  ";
            }
            else {
                // If validity 0 and locked == getting reedemed
                _locked = ownerData>>MPOS_LOCKED & BOOL_MASK;
                if (_locked == 1) {
                    color = "b50"; // orange
                    validityText = "REDEEM PENDING  ";
                }
                else {
                    color = "0a0"; // green
                }
            }
        }
        else {
            color = "b00"; // red, invalid
        }
        assembly {
            let dst := add(b, 1344)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), color))
            // VALID => INVALID
            if gt(_validityIdx, VALID) {
                dst := add(b, 1349)
                mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), "IN"))
            }
            // INVALID => LOCKED
            if eq(_locked, 1) {
                dst := add(b, 1349)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), " LOCKED"))
            }
            // INVALID => DEAD (grayscaled)
            if gt(_validityIdx, 3) {
                dst := add(b, 790)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "0"))
                dst := add(b, 1349)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), "   DEAD"))
            }
            // Add validity text next to status
            dst := add(b, 1357)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), ">>"))
            dst := add(b, 1360)
            mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), validityText))
        }
    }

    /*
     * @dev Adds the `_token` information of fixed sized fields to hardcoded 
     * bytes `b`.
     */
    function addNFTAge(uint256 data, bytes memory b)
    private view {
        bytes6 _periods = getNFTAge(
            _viewPackedData(data, UPOS_MINTSTAMP, USZ_TIMESTAMP)
        );
        assembly {
            // Timestamps
            let dst := add(b, 1607)
            let mask := shl(208, 0xFFFF00000000)
            let srcpart := and(_periods, mask)
            let destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 1610)
            mask := shl(208, 0x0000FFFF0000)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 1613)
            mask := shl(208, 0x00000000FFFF)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
        }
    }

    function addTokenIdText(bytes6 bTokenId)
    private pure
    returns (bytes memory bT) {
        bT = "<text x='50%' y='625' text-anchor='middle' style='font-family:\"Helvetica\";font-size:78px;fill#111;'>* 0XXXXX  *</text>";
        bytes1 tokenLead = bTokenId[0];
        assembly {
            let dst := add(bT, 135)
            if eq(tokenLead, "0") {
                dst := add(bT, 41)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "4"))
                dst := add(bT, 134)
            }
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), bTokenId))
        }
    }

    function addTokenInfo(uint256 ownerData, uint256 data, uint256 validity, string memory _name, bytes memory b)
    private view {
        bytes7 _tagtxt = genTagsToAscii(
            _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG),
            _viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG)
        );
        bytes7 _tushtxt = genTagsToAscii(
            _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH),
            _viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH)
        );
        bytes4 __mintid = Helpers.flip4Space(
            bytes4(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_EDITION_MINT_ID, USZ_EDITION_MINT_ID)
            ))
        );
        bytes4 _royalty = Helpers.bpsToPercent(
            _viewPackedData(ownerData, MPOS_ROYALTY, MSZ_ROYALTY)*10
        );
        bytes2 _edition = Helpers.flip2Space(
            Helpers.remove2Null(
                bytes2(Helpers.uintToBytes(
                    _viewPackedData(data, UPOS_EDITION, USZ_EDITION)
                ))
            )
        );
        (uint256 _bgidx, bytes16 _classer) = _getRarityTier(
            _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG),
            _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER),
            _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL)
        );
        bytes3 _rgc2 = validity < 4 ? hex3[_bgidx] : bytes3("888");
        bytes2 _namesize = getNameSize(uint256(bytes(_name).length));
    
        assembly {
            // Name Font Size
            let dst := add(b, 298)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _namesize))
            // Colors
            dst := add(b, 495)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _rgc2))
            // Royalty
            dst := add(b, 1415)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _royalty))
            // Classer
            dst := add(b, 1501)
            mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _classer))
            // Edition
            let _edcheck := gt(_edition, 9)
            switch _edcheck case 0 {
                dst := add(b, 1571)
            } default {
                dst := add(b, 1570)
            }
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _edition))
            // Mintid
            dst := add(b, 1573)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintid))
            // Gen Country Text
            dst := add(b, 1786)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), _tagtxt))
            dst := add(b, 1796)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), _tushtxt))
        }
    }

    /** 
     * @dev The Korea4L and embroidered tush tags have a marker added that 
     * differentiates their display versus standard Korea5L and Canadian tush 
     * tags. The provides the user with the information necessary to know 
     * what type of tag is present based on the SVG display alone.
     */
    function addTushMarker(uint256 markerTush, uint256 genTag)
    private view
    returns (bytes memory e) {
        if (markerTush > 0) {
            e = "<text x='555' y='726' class='c9Ts c9Tb' style='opacity:0.8;font-family:\"Brush Script MT\",cursive;fill:#222;' text-anchor='middle'>4L  </text>";

            bytes4 x = _vMarkers[markerTush-1];
            bytes4 y = x == bytes4("CE  ") ?
                bytes4("c e ") :
                x == bytes4("EMBF") ?
                    bytes4("embF") :
                    x == bytes4("EMBS") ?
                        bytes4("embS") : x;
            assembly {
                let dst := add(e, 162)
                mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), y))
                switch genTag case 0 {
                    dst := add(e, 135)
                    mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), "eee"))
                }
            }
            if (markerTush > 4) { // Korean bs on hang tag
                assembly {
                    let dst := add(e, 41)
                    mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), "75 "))
                }
            }
        }
    }

    function _href(bytes6 b6TokenId)
    private pure
    returns (bytes memory href) {
        href = "<a href='https://collect9.io/nft/XXXXXX' target='_blank'>";
        assembly {
            let dst := add(href, 65)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
        }
    }

    function _wrapInHref(bytes6 b6TokenId, bytes memory b)
    private pure
    returns (bytes memory) {
        return bytes.concat(_href(b6TokenId), b, "</a>");
    }

    function getBarCodeGroup(uint256 tokenId, bytes6 b6TokenId, uint256 barCodeData)
    private pure
    returns (bytes memory gb) {
        gb = "<g transform='translate(XXX 646) scale(0.33)'>";
        bytes3 x = tokenId > 10**5 ? bytes3("393") : bytes3("440");
        assembly {
            let dst := add(gb, 56)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), x))
        }
        gb = bytes.concat(
            gb,
            barCodeSVG(b6TokenId, barCodeData),
            "</g>"
        );
    }

    function getLogoGroup(bytes6 bTokenId)
    private view
    returns (bytes memory) {
        return bytes.concat(
            "<g transform='translate(470 6) scale(0.2)' fill-opacity='0.89'>",
            _wrapInHref(bTokenId, C9SVGLogo(contractLogo).getSVGLogo()),
            "</g>"
        );
    }

    function getFlagsGroup(uint256 tokenData)
    public view
    returns (bytes memory fb) {
        bytes memory _flagTag = C9SVGFlags(contractFlags).getSVGFlag(
            _viewPackedData(tokenData, UPOS_CNTRYTAG, USZ_CNTRYTAG)
        );
        bytes memory _flagTush = C9SVGFlags(contractFlags).getSVGFlag(
            _viewPackedData(tokenData, UPOS_CNTRYTUSH, USZ_CNTRYTUSH)
        );
        fb = bytes.concat(
            "<g transform='translate(20 580) scale(0.18)'>",
            _flagTag,
            "<g transform='translate(2648)'>",
            _flagTush,
            "</g></g>"
        );
    }

    /**
     * @dev The SVG output memory `b` is finished off with the variable sized parts of `_token`.
     * This is a bit messy but bytes concat seems to get the job done.
     */
    function addVariableBytes(uint256 tokenId, bytes6 b6TokenId, uint256 tokenData, uint256 barCodeData, uint256 qrCodeData, string memory name)
    private view
    returns(bytes memory vb) {
        
        // bytes memory _qrCodeSVG = qrCodeSVG(qrCodeData);
    
        vb = bytes.concat(
            bytes(name), "</text></g>",
            qrCodeSVGGroup(qrCodeData),
            getFlagsGroup(tokenData),
            getBarCodeGroup(tokenId, b6TokenId, barCodeData)            
        );
    }

    /**
     * @dev If token has been upgraded, add text that shows it has.
     */
    function addUpgradeText(uint256 upgraded)
    private pure
    returns (bytes memory upgradedText) {
        if (upgraded == UPGRADED) {
            upgradedText = "<text x='320' y='92' style='font-family:\"Brush Script MT\",cursive;font-size:26px;fill:#050'>-Upgraded</text>";
        }
    }

    /**
     * @dev Ghost tiers get a little more fun. They get a nebula-like background 
     * that's one of 4 color templates chosen pseudo-random to the viewer 
     * at each call. OpenSea, Rarible etc. will cache one at random, 
     * but users should be able to fetch meta-data updates to see 
     * color changes.
     */
    function setBackground(uint256 genTag, uint256 specialTier, bytes memory b)
    private pure {
        bytes23[11] memory matrices = [
            bytes23("1 0 0 0 1 0 1 0 0 1 1 0"), //g0
            "1 1 0 0 1 1 1 0 0 1 1 1",  //g1
            "0 0 0 0 1 0 1 0 0 1 1 0",  //g2
            "1 0 0 0 1 0 0 0 0 1 0 0",  //g3
            "0 0 0 0 1 0 0 0 0 1 0 0",  //g4
            "0 0 0 0 1 0 0 0 0 1 0 0",  //g5
            "0 0 0 0 1 1 0 0 0 1 1 1",  //spec
            "1 0 0 1 1 1 0 0 0 1 1 0",  //emb
            "0 0 0 0 1 0 0 0 0 1 0 0",  //odd
            "1 0 0 0 1 0 0 0 0 1 1 0",  //finite
            "0 1 0 0 1 0 0 1 0 1 1 0"   //proto
        ];

        bytes10[11] memory filters = [
            bytes10("0 .0 .0 .9"), //g0
            "1 .4 .1 .1", //g1
            "5 .1 .1 .2", //g2
            "2 .0 .0 .6", //g3
            "0 .0 .0 .3", //g4
            "0 .0 .0 .3", //g5
            "9 .2 .2 .8", //spec
            "5 .2 .8 .9", //emb
            "9 .0 .0 .8", //odd
            "8 .2 .8 .2", //finite
            "9 .9 .9 .9" //proto
        ];

        bytes5[11] memory frequencies = [
            bytes5("0.003"),
            "0.006",
            "0.002",
            "0.004",
            "0.206",
            "2.006",
            "0.002",
            "0.001",
            "0.008",
            "0.001",
            "0.003"
        ];

        bytes1[11] memory octaves = [bytes1("3"), "2", "1", "2", "1", "8", "1", "1", "1", "1", "8"];

        bytes23 matrix = specialTier > 0 ? matrices[specialTier+5] : matrices[genTag];
        bytes11 filter = specialTier > 0 ? filters[specialTier+5] : filters[genTag];
        bytes5 freq = specialTier > 0 ? frequencies[specialTier+5] : frequencies[genTag];
        bytes1 octave = specialTier > 0 ? octaves[specialTier+5] : octaves[genTag];

        assembly {
            let dst := add(b, 584)
            mstore(dst, or(and(mload(dst), not(shl(216, 0xFFFFFFFFFF))), freq))
            dst := add(b, 603)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), octave))
            dst := add(b, 680)
            mstore(dst, or(and(mload(dst), not(shl(72, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), matrix))
            dst := add(b, 709)
            mstore(dst, or(and(mload(dst), not(shl(176, 0xFFFFFFFFFFFFFFFFFFFF))), filter))
        }
    }

    /**
     * @dev Converts integer inputs to the ordinal country ascii text representation 
     * based on input params `_gentag` and `_tag`.
     */
    function genTagsToAscii(uint256 _gentag, uint256 _tag)
    private view returns(bytes7) {
        bytes3 __gentag = Helpers.uintToOrdinal(_gentag);
        bytes3 _cntrytag = _vFlags[_tag];
        bytes memory _tmpout = "       ";
        assembly {
            let dst := add(_tmpout, 32)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), __gentag))
            if lt(_tag, 7) {
                dst := add(_tmpout, 36)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            }
        }
        return bytes7(_tmpout);
    }

    /**
     * @dev Since SVG text does not automatically contain itself to bounds, 
     * this function returns the font size of text depending on input `len` 
     * so that it stays contained.
     */
    function getNameSize(uint256 len)
    private pure returns(bytes2) {
        if (len < 11) {
            return "52";
        }
        else if (len > 17) {
            return "30";
        }
        else {
            uint256 adjuster = (len-10)*3;
            uint256 fontsize = 52 - adjuster;
            return bytes2(Helpers.uintToBytes(fontsize));
        }
    }

    /**
     * @dev Returns the age of the NFT in a packed bytes6 array that is 
     * years, months, days 2 bytes each. Note: Due to precision errors on 
     * number of seconds of per year, month, etc. There's a 
     * chance that the number of days can be negative which causes VM revert. 
     * To get around that, just display as zero. Just in case this can 
     * happen for months as well, that has been implemented too.
     */
    function getNFTAge(uint256 _mintstamp)
    private view returns(bytes6) {
        uint256 _ds = block.timestamp - _mintstamp;
        uint256 _nyrs = _ds/31556926;

        uint256 _nmonths = 0;
        uint256 _nmonthsp1 = _ds/2629743;
        uint256 _nmonthsp2 = 12*_nyrs;
        if (_nmonthsp1 > _nmonthsp2) {
            _nmonths = _nmonthsp1 - _nmonthsp2;
        }
        
        uint256 _ndays = 0;
        uint256 _ndaysp1 = _ds/86400;
        uint256 _ndaysp2 = (3652500*_nyrs + 304375*_nmonths)/10000;
        if (_ndaysp1 > _ndaysp2) {
            _ndays = _ndaysp1 - _ndaysp2;
        }

        bytes32 _byrs = Helpers.uintToBytes(_nyrs);
        bytes32 _bmonths = Helpers.uintToBytes(_nmonths);
        bytes32 _bdays = Helpers.uintToBytes(_ndays);
        bytes memory _periods = new bytes(6);
        assembly {
            let dst := add(_periods, 32)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _byrs))
            dst := add(_periods, 34)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _bmonths))
            dst := add(_periods, 36)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _bdays))
        }
        Helpers.flipSpace(_periods, 0);
        Helpers.flipSpace(_periods, 2);
        Helpers.flipSpace(_periods, 4);
        return bytes6(_periods);
    }

    /**
     * @dev External function to call and return the SVG string built from `_token`  
     * and owner `_address`.
     */
    function svgImage(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    returns (string memory) {
        string memory name = IC9Token(contractToken).getTokenParamsName(tokenId);
        bytes6 b6TokenId = Helpers.tokenIdToBytes(tokenId);
        (uint256 qrCodeData, uint256 barCodeData) = splitQRData(codeData);

        bytes memory bSVG = SVG_OPENER;
        addIds(b6TokenId, bSVG);
        addTokenInfo(ownerData, tokenData, _currentVId(ownerData), name, bSVG);
        addAddress(IC9Token(contractToken).ownerOf(tokenId), bSVG);
        addNFTAge(tokenData, bSVG);
        addValidityInfo(tokenId, ownerData, bSVG);
        setBackground(
            _viewPackedData(tokenData, UPOS_GENTAG, USZ_GENTAG),
            _viewPackedData(tokenData, UPOS_SPECIAL, USZ_SPECIAL),
            bSVG
        );

        // Logo
        bytes memory bL = getLogoGroup(b6TokenId);
        // Variable bytes group
        bytes memory vB = addVariableBytes(tokenId, b6TokenId, tokenData, barCodeData, qrCodeData, name);
        // Tush marker group
        bytes memory mT = addTushMarker(
            _viewPackedData(tokenData, UPOS_MARKERTUSH, USZ_MARKERTUSH),
            _viewPackedData(tokenData, UPOS_GENTAG, USZ_GENTAG)
        );
        // Upgraded text
        bytes memory uT = addUpgradeText(ownerData>>MPOS_UPGRADED & BOOL_MASK);

        return string(bytes.concat(bSVG, vB, mT, uT, bL, "</g></svg>"));
    }

    function splitQRData(uint256 packed)
    private pure
    returns (uint256 qrCodeData, uint256 barCodeData) {
        qrCodeData = uint256(uint168(packed));
        barCodeData = packed >> 168;
    }

    function getBoolean256(uint256 _packedBools, uint256 _boolNumber)
    private pure
    returns (uint256 flag)
    {
        flag = (_packedBools >> _boolNumber) & uint256(1);
    }

    function uintToBytes(uint256 v)
    private pure
    returns (bytes32 ret) {
        if (v == 0) {
            ret = '0';
        }
        else {
            while (v > 0) {
                ret = bytes32(uint256(ret) / (2 ** 8));
                ret |= bytes32(((v % 10) + 48) * 2 ** (8 * 31));
                v /= 10;
            }
        }
        return ret;
    }

    function uintToDigit(uint256 input)
    private pure
    returns (bytes1) {
        return bytes1(uintToBytes(input));
    }

    function uintToStr(uint256 input)
    private pure
    returns (bytes2) {
        bytes32 b32Input = uintToBytes(input);
        bytes memory output = new bytes(2);
        output[0] = b32Input[0];
        output[1] = b32Input[1];

        if (input < 10) output[1] = 0x20;
        
        return bytes2(output);
    }

    function toXY(uint256 index)
    private pure
    returns (uint256 y, uint256 x) {
        // Convert to true bit index
        unchecked {index += 28;}
        if (index > 31) {unchecked {index += 10;}}
        if (index > 48) {unchecked {index += 10;}}
        if (index > 67) {unchecked {index += 8;}}
        if (index > 84) {unchecked {index += 9;}}
        if (index > 97) {unchecked {index += 3;}}
        if (index > 101) {unchecked {index += 8;}}
        if (index > 114) {unchecked {index += 12;}}
        if (index > 133) {unchecked {index += 6;}}
        if (index > 142) {unchecked {index += 4;}}
        if (index > 149) {unchecked {index += 4;}}
        if (index > 183) {unchecked {index += 2;}}
        if (index > 199) {unchecked {index += 3;}}
        if (index > 214) {unchecked {index += 7;}}
        if (index > 236) {unchecked {index += 2;}}
        if (index > 252) {unchecked {index += 3;}}
        if (index > 282) {unchecked {index += 2;}}
        unchecked {
            y = index / 17;
            x = index - y*17;
        }
    }

    function _toRect(uint256 x, uint256 y)
    private pure
    returns (bytes memory) {
        return bytes.concat(
            "<rect x='",
            uintToStr(x),
            "' y='",
            uintToStr(y),
            "'/>"
        );
    }

    function _toBar(uint256 x, uint256 multi)
    private pure
    returns (bytes memory b) {
        b = bytes.concat(
            "<rect x='",
            uintToStr(x),
            "' width='",
            uintToDigit(multi),
            "'/>"
        );
    }

    function toRect(uint256 index)
    private pure
    returns (bytes memory) {
        (uint256 y, uint256 x) = toXY(index);
        return _toRect(x, y);
    }

    function packedToRects(uint256 packed)
    private pure 
    returns (bytes memory rects) {
        uint256 bitSwitch;
        for (uint256 i; i<168;) {
            bitSwitch = getBoolean256(packed, (168-i));
            if (bitSwitch == 1) {
                rects = bytes.concat(
                    rects,
                    toRect(i)
                );
            }
            unchecked {++i;}
        }
    }

    function qrCodeSVG(uint256 packed)
    public pure
    returns (bytes memory svg) {
        svg = bytes.concat(
            QR_CODE_BASE,
            packedToRects(packed),
            "</svg>"
        );
    }

    function qrCodeSVGGroup(uint256 packed)
    private pure
    returns (bytes memory svg) {
        svg = bytes.concat(
            "<g transform='translate(157.5 146) scale(0.5)'>",
            qrCodeSVG(packed),
            "</g>"
        );
    }

    function barCodeRects(uint256 packed)
    private pure
    returns (bytes memory rects) {
        uint256 j;
        for (uint256 i; i<86;) {
            j = 1;
            if (getBoolean256(packed, i) == 1) {
                for (j; j<4;) {                    
                    if (getBoolean256(packed, i+j) == 0) {
                        break;
                    }
                    unchecked {++j;}
                }
                rects = bytes.concat(
                    rects,
                    _toBar(i+14, j)
                );
            }
            unchecked {i += j;}
        }
    }

    function barCodeSVG(bytes6 b6TokenId, uint256 barCodeData)
    private pure
    returns (bytes memory svg) {
        bytes memory bT = addTokenIdText(b6TokenId);
        svg = bytes.concat(
            BAR_CODE_BASE,
            barCodeRects(barCodeData),
            "</g></svg>",
            bT
        );
    }
}