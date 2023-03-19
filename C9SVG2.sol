// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Shared.sol";
import "./abstract/C9Struct4.sol";
import "./interfaces/IC9SVG2.sol";
import "./interfaces/IC9Token.sol";
import "./utils/C9Context.sol";
import "./utils/Helpers.sol";




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
            ".c9Tsvg rect{width:100%;height:100%;} "
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
                "<feTurbulence type='fractalNoise' baseFrequency='.2' numOctaves='8'/>"
                "<feComposite in2='SourceGraphic' operator='in'/>"
                "<feColorMatrix values='1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0 0 .2 0'/>"
            "</filter>"
            "<filter id='c9Gs'>"
                "<feColorMatrix type='saturate' values='1.0'/>"
            "</filter>"
        "</defs>"
        "<g filter='url(#c9Gs)'>"
            "<rect rx='20' fill='url(#rgXXXXXX)'/>"
            "<rect rx='20' filter='url(#c9Nse)'/>"
            "<g transform='translate(20 20)' style='fill:#ded;'>"
                "<rect style='width:590px;height:150px;' rx='10'/>"
                "<rect y='720' style='width:590px;height:120px;' rx='10'/>"
            "</g>"
            "<rect y='560' style='height:22px;fill:#ddf;fill-opacity:0.6;'/>"
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

    bytes constant FLG_BLK = ""
        "<pattern id='ptrn' width='.1' height='.1'>"
            "<rect width='64' height='48' fill='#def' stroke='#000'/>"
        "</pattern>"
        "<path d='M0 0h640v480H0z' fill='url(#ptrn)'/>";
        
    bytes constant FLG_CAN = ""
        "<path fill='#fff' d='M0 0h640v480H0z'/>"
        "<path fill='#d21' d='M-19.7 0h169.8v480H-19.7zm509.5 0h169.8v480H489.9zM201 232l-13.3 4.4 61.4 54c4.7 13.7-1.6 "
        "17.8-5.6 25l66.6-8.4-1.6 67 13.9-.3-3.1-66.6 66.7 8c-4.1-8.7-7.8-13.3-4-27.2l61.3-51-10.7-4c-8.8-6.8 3.8-32.6 "
        "5.6-48.9 0 0-35.7 12.3-38 5.8l-9.2-17.5-32.6 35.8c-3.5.9-5-.5-5.9-3.5l15-74.8-23.8 13.4c-2 .9-4 .1-5.2-2.2l-23-46-23.6 "
        "47.8c-1.8 1.7-3.6 1.9-5 .7L264 130.8l13.7 74.1c-1.1 3-3.7 3.8-6.7 2.2l-31.2-35.3c-4 6.5-6.8 17.1-12.2 19.5-5.4 "
        "2.3-23.5-4.5-35.6-7 4.2 14.8 17 39.6 9 47.7z'/>";

    bytes constant FLG_CHN = ""
        "<g id='c9chn'>"
            "<path fill='#ff0' d='M-.6.8 0-1 .6.8-1-.3h2z'/>"
        "</g>"
        "<path fill='#e12' d='M0 0h640v480H0z'/>"
        "<use href='#c9chn' transform='matrix(72 0 0 72 120 120)'/>"
        "<use href='#c9chn' transform='matrix(-12.3 -20.6 20.6 -12.3 240.3 48)'/>"
        "<use href='#c9chn' transform='matrix(-3.4 -23.8 23.8 -3.4 288 96)'/>"
        "<use href='#c9chn' transform='matrix(6.6 -23 23 6.6 288 168)'/>"
        "<use href='#c9chn' transform='matrix(15 -18.7 18.7 15 240 216)'/>";

    bytes constant FLG_GER = ""
        "<path fill='#fc0' d='M0 320h640v160H0z'/>"
        "<path d='M0 0h640v160H0z'/>"
        "<path fill='#d00' d='M0 160h640v160H0z'/>";

    bytes constant FLG_IND = ""
        "<path fill='#e01' d='M0 0h640v249H0z'/>"
        "<path fill='#fff' d='M0 240h640v240H0z'/>";

    bytes constant FLG_KOR = ""
        "<defs>"
            "<clipPath id='c9kor1'>"
                "<path fill-opacity='.7' d='M-95.8-.4h682.7v512H-95.8z'/>"
            "</clipPath>"
        "</defs>"
        "<g fill-rule='evenodd' clip-path='url(#c9kor1)' transform='translate(89.8 .4) scale(.94)'>"
            "<path fill='#fff' d='M-95.8-.4H587v512H-95.8Z'/>"
            "<g transform='rotate(-56.3 361.6 -101.3) scale(10.67)'>"
                "<g id='c9kor2'>"
                    "<path id='c9kor3' d='M-6-26H6v2H-6Zm0 3H6v2H-6Zm0 3H6v2H-6Z'/>"
                    "<use href='#c9kor3' y='44'/>"
                "</g>"
                "<path stroke='#fff' d='M0 17v10'/>"
                "<path fill='#c33' d='M0-12a12 12 0 0 1 0 24Z'/>"
                "<path fill='#04a' d='M0-12a12 12 0 0 0 0 24A6 6 0 0 0 0 0Z'/>"
                "<circle cy='-6' r='6' fill='#c33'/>"
            "</g>"
            "<g transform='rotate(-123.7 191.2 62.2) scale(10.67)'>"
                "<use href='#c9kor2'/>"
                "<path stroke='#fff' d='M0-23.5v3M0 17v3.5m0 3v3'/>"
            "</g>"
        "</g>";

    bytes constant FLG_UK  = ""
        "<path fill='#026' d='M0 0h640v480H0z'/>"
        "<path fill='#fff' d='m75 0 244 181L562 0h78v62L400 241l240 178v61h-80L320 301 81 480H0v-60l239-178L0 64V0h75z'/>"
        "<path fill='#c12' d='m424 281 216 159v40L369 281h55zm-184 20 6 35L54 480H0l240-179zM640 0v3L391 191l2-44L590 0h50zM0 0l239 176h-60L0 42V0z'/>"
        "<path fill='#fff' d='M241 0v480h160V0H241zM0 160v160h640V160H0z'/>"
        "<path fill='#c12' d='M0 193v96h640v-96H0zM273 0v480h96V0h-96z'/>";

    bytes constant FLG_US  = ""
        "<path fill='#fff' d='M0 0h640v480H0z'/>"
        "<g id='c9uss'>"
            "<path fill='#fff' d='m30.4 11 3.4 10.3h10.6l-8.6 6.3 3.3 10.3-8.7-6.4-8.6 6.3L25 27.6l-8.7-6.3h10.9z'/>"
        "</g>"
        "<g id='c9uso'>"
            "<use href='#c9uss'/>"
            "<use href='#c9uss' y='51.7'/>"
            "<use href='#c9uss' y='103.4'/>"
            "<use href='#c9uss' y='155.1'/>"
            "<use href='#c9uss' y='206.8'/>"
        "</g>"
        "<g id='c9use'>"
            "<use href='#c9uss' y='25.9'/>"
            "<use href='#c9uss' y='77.6'/>"
            "<use href='#c9uss' y='129.5'/>"
            "<use href='#c9uss' y='181.4'/>"
        "</g>"
        "<g id='c9usa'>"
            "<use href='#c9uso'/>"
            "<use href='#c9use' x='30.4'/>"
        "</g>"
        "<path fill='#b02' d='M0 0h640v37H0zm0 73.9h640v37H0zm0 73.8h640v37H0zm0 73.8h640v37H0zm0 74h640v36.8H0zm0 73.7h640v37H0zM0 443h640V480H0z'/>"
        "<path fill='#026' d='M0 0h364.8v259H0z'/>"
        "<use href='#c9usa'/>"
        "<use href='#c9usa' x='60.8'/>"
        "<use href='#c9usa' x='121.6'/>"
        "<use href='#c9usa' x='182.4'/>"
        "<use href='#c9usa' x='243.2'/>"
        "<use href='#c9uso' x='304'/>";

    function getSVGFlag(uint256 flagId)
    public pure
    returns(bytes memory flag) {
        flag = "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 640 480'>";
        if (flagId == 0) {
            flag = bytes.concat(flag, FLG_CAN);
        }
        else if (flagId == 1) {
            flag = bytes.concat(flag, FLG_CHN);
        }
        else if (flagId == 2) {
            flag = bytes.concat(flag, FLG_GER);
        }
        else if (flagId == 3) {
            flag = bytes.concat(flag, FLG_IND);
        }
        else if (flagId == 4) {
            flag = bytes.concat(flag, FLG_KOR);
        }
        else if (flagId == 5) {
            flag = bytes.concat(flag, FLG_UK);
        }
        else if (flagId == 6) {
            flag = bytes.concat(flag, FLG_US);
        }
        else {
            flag = bytes.concat(flag, FLG_BLK);
        }
        flag = bytes.concat(flag, "</svg>");
    }

    //     // LOGO WRAPPED
    //     // "<g transform='translate(470 6) scale(0.2)' fill-opacity='0.89'>"
    //     // "<a href='https://collect9.io' target='_blank'>"
    //     // "</a>"
    //     // "</g>"

    address public immutable contractToken;

    constructor (address _contractToken) {
        contractToken = _contractToken;
    }

       /**
     * @dev Adds the bytes32 + bytes8 representation of the address into the 
     * SVG output memory.
     */
    function addAddress(address _address, bytes memory b) private pure {
        (bytes32 _a1, bytes8 _a2) = Helpers.addressToB32B8(_address);
        assembly {
            mstore(add(b, 1678), _a1)
            let dst := add(b, 1710)
            mstore(dst, or(and(mload(dst), not(shl(192, 0xFFFFFFFFFFFFFFFF))), _a2))
        }
    }

    /**
     * @dev Adds the `_id` into the SVG output memory `b`. 
     * Note: this is done so that multiple 
     * SVGs may be displayed on the same page without CSS conflict.
     */
    function addIds(bytes6 b6Tokenid, bytes memory b)
    private pure {
        assembly {
            let dst := add(b, 375)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6Tokenid))
            dst := add(b, 869)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6Tokenid))
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
            let dst := add(b, 1314)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), color))
            // VALID => INVALID
            if gt(_validityIdx, VALID) {
                dst := add(b, 1319)
                mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), "IN"))
            }
            // INVALID => LOCKED
            if eq(_locked, 1) {
                dst := add(b, 1319)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), " LOCKED"))
            }
            // INVALID => DEAD (grayscaled)
            if gt(_validityIdx, 3) {
                dst := add(b, 797)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "0"))
                dst := add(b, 1319)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), "   DEAD"))
            }
            // Add validity text next to status
            dst := add(b, 1327)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), ">>"))
            dst := add(b, 1330)
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
            let dst := add(b, 1577)
            let mask := shl(208, 0xFFFF00000000)
            let srcpart := and(_periods, mask)
            let destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 1580)
            mask := shl(208, 0x0000FFFF0000)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 1583)
            mask := shl(208, 0x00000000FFFF)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
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
            _viewPackedData(ownerData, MPOS_ROYALTY, MSZ_ROYALTY)
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
            let dst := add(b, 309)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _namesize))
            // Colors
            dst := add(b, 506)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _rgc2))
            // Royalty
            dst := add(b, 1385)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _royalty))
            // Classer
            dst := add(b, 1471)
            mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _classer))
            // Edition
            let _edcheck := gt(_edition, 9)
            switch _edcheck case 0 {
                dst := add(b, 1541)
            } default {
                dst := add(b, 1540)
            }
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _edition))
            // Mintid
            dst := add(b, 1543)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintid))
            // Gen Country Text
            dst := add(b, 1756)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), _tagtxt))
            dst := add(b, 1766)
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

    function _href(uint256 tokenId)
    private pure
    returns (bytes memory href) {
        bytes6 b6TokenId =  Helpers.tokenIdToBytes(tokenId);
        href = "<a href='https://collect9.io/nft/XXXXXX' target='_blank'>";
        assembly {
            let dst := add(href, 65)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
        }
    }

    function _wrapInHref(uint256 tokenId, bytes memory b)
    private pure
    returns (bytes memory) {
        return bytes.concat(_href(tokenId), b, "</a>");
    }

    function getBarCodeGroup(uint256 tokenId, uint256 barCodeData)
    private pure
    returns (bytes memory gb) {
        gb = "<g transform='translate(XXX 646) scale(0.33)'>";
        bytes3 x = tokenId > 10**5 ? bytes3("385") : bytes3("400");
        assembly {
            let dst := add(gb, 64)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), x))
        }
        gb = bytes.concat(
            gb,
            barCodeSVG(barCodeData),
            "</g>"
        );
    }

    function getFlagsGroup(uint256 tokenData)
    public pure
    returns (bytes memory fb) {
        bytes memory _flagTag = getSVGFlag(
            _viewPackedData(tokenData, UPOS_CNTRYTAG, USZ_CNTRYTAG)
        );
        bytes memory _flagTush = getSVGFlag(
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
    function addVariableBytes(uint256 tokenId, uint256 tokenData, uint256 barCodeData, uint256 qrCodeData, string memory name)
    private pure
    returns(bytes memory vb) {
        
        // bytes memory _qrCodeSVG = qrCodeSVG(qrCodeData);
    
        vb = bytes.concat(
            bytes(name), "</text></g>",
            getFlagsGroup(tokenData)
            //getBarCodeGroup(tokenId, barCodeData)            
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
    function checkForSpecialBg(uint256 rarityTier, bytes memory b)
    private view {
        bytes32 _filter_mod = "turbulence' baseFrequency='0.002";
        bytes32[3] memory mods = [bytes32(
            "1 1 0 0 0 1 0 0 0 0 0 1 0 0 0 0 "),
            "0 0 0 0 1 1 0 0 0 0 0 1 0 0 0 0 ",
            "0 0 0 0 0 1 0 0 0 0 0 1 1 1 0 0 "];
        if (rarityTier == 0) {
            assembly {
                let dst := add(b, 594)
                mstore(dst, _filter_mod)
                dst := add(b, 640)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "4"))
                dst := add(b, 753)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "9"))
            }
            uint256 psrand = block.timestamp % 4;
            if (psrand < 4) {
                bytes32 _colormod = mods[psrand];
                assembly {
                    let dst := add(b, 715)
                    mstore(dst, _colormod)
                }
            }
        }
    }

    /**
     * @dev Converts integer inputs to the ordinal country ascii text representation 
     * based on input params `_gentag` and `_tag`.
     */
    function genTagsToAscii(uint256 _gentag, uint256 _tag) private view returns(bytes7) {
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
    function getNameSize(uint256 len) private pure returns(bytes2) {
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
    function getNFTAge(uint256 _mintstamp) private view returns(bytes6) {
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
        
        bytes memory vB = addVariableBytes(tokenId, tokenData, barCodeData, qrCodeData, name);
        bytes memory mT = addTushMarker(
            _viewPackedData(tokenData, UPOS_MARKERTUSH, USZ_MARKERTUSH),
            _viewPackedData(tokenData, UPOS_GENTAG, USZ_GENTAG)
        );
        bytes memory uT = addUpgradeText(ownerData>>MPOS_UPGRADED & BOOL_MASK);


        // checkForSpecialBg(_viewPackedData(tokenData, UPOS_SPECIAL, USZ_SPECIAL), b);

        return string(bytes.concat(bSVG, vB, mT, uT, "</g></svg>"));



    }

    function splitQRData(uint256 packed)
    public pure
    returns (uint256 qrCodeData, uint256 barCodeData) {
        qrCodeData = uint256(uint168(packed));
        barCodeData = packed >> 170;
    }

    function getBoolean8(uint256 _packedBools, uint256 _boolNumber)
    public pure
    returns (uint8 flag)
    {
        flag = uint8((_packedBools >> _boolNumber) & uint256(1));
    }

    function getBoolean256(uint256 _packedBools, uint256 _boolNumber)
    public pure
    returns (uint256 flag)
    {
        flag = (_packedBools >> _boolNumber) & uint256(1);
    }

    function uintToBytes(uint256 v)
    internal pure
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
    public pure
    returns (bytes1) {
        return bytes1(uintToBytes(input));
    }

    function uintToStr(uint256 input)
    public pure
    returns (bytes2) {
        bytes32 b32Input = uintToBytes(input);
        bytes memory output = new bytes(2);
        output[0] = b32Input[0];
        output[1] = b32Input[1];

        if (input < 10) output[1] = 0x20;
        
        return bytes2(output);
    }

    function toXY(uint256 index)
    public pure
    returns (uint256 y, uint256 x) {
        // Convert to true bit index
        if (index > 3) {
            unchecked {index += 10;}
        }
        unchecked {index += 28;}
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
    public pure
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
    public pure
    returns (bytes memory) {
        (uint256 y, uint256 x) = toXY(index);
        return _toRect(x, y);
    }

    
    function packedToBits(uint256 packed)
    public pure
    returns (uint8[256] memory bits) {
        for (uint256 i; i<256;) {
            bits[i] = getBoolean8(packed, (255-i));
            unchecked {++i;}
        }
    }

    function packedToRects(uint256 packed)
    public pure 
    returns (bytes memory rects) {
        uint256 bitSwitch;
        for (uint256 i; i<251;) {
            bitSwitch = getBoolean256(packed, (255-i));
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

    function barCodeGroups(uint256 packed)
    public pure
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

    function barCodeSVG(uint256 packed)
    public pure
    returns (bytes memory svg) {
        svg = bytes.concat(
            BAR_CODE_BASE,
            barCodeGroups(packed),
            "</g></svg>"
        );
    }
}