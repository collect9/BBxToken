// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "./utils/Helpers.sol";
import "./C9Shared.sol";


/**
* @dev A validity flag has been added, in the event royalties are 
* not paid then the token is no longer redeemable.
*/
interface IC9SVG {
    function returnSVG(address _address, C9Shared.TokenInfo calldata _token) external view returns (string memory);
}

contract C9SVG is IC9SVG, C9Shared {
    bytes constant flg_blk = "<pattern id='ptrn' width='.1' height='.1'><rect width='64' height='48' fill='#def' stroke='#000'/></pattern><path d='M0 0h640v480H0z' fill='url(#ptrn)'/>"; //blank flag
    bytes constant flg_can = "<path fill='#fff' d='M0 0h640v480H0z'/><path fill='#d21' d='M-19.7 0h169.8v480H-19.7zm509.5 0h169.8v480H489.9zM201 232l-13.3 4.4 61.4 54c4.7 13.7-1.6 17.8-5.6 25l66.6-8.4-1.6 67 13.9-.3-3.1-66.6 66.7 8c-4.1-8.7-7.8-13.3-4-27.2l61.3-51-10.7-4c-8.8-6.8 3.8-32.6 5.6-48.9 0 0-35.7 12.3-38 5.8l-9.2-17.5-32.6 35.8c-3.5.9-5-.5-5.9-3.5l15-74.8-23.8 13.4c-2 .9-4 .1-5.2-2.2l-23-46-23.6 47.8c-1.8 1.7-3.6 1.9-5 .7L264 130.8l13.7 74.1c-1.1 3-3.7 3.8-6.7 2.2l-31.2-35.3c-4 6.5-6.8 17.1-12.2 19.5-5.4 2.3-23.5-4.5-35.6-7 4.2 14.8 17 39.6 9 47.7z'/>";
    bytes constant flg_chn = "<g id='c9chn'><path fill='#ff0' d='M-.6.8 0-1 .6.8-1-.3h2z'/></g><path fill='#e12' d='M0 0h640v480H0z'/><use href='#c9chn' transform='matrix(72 0 0 72 120 120)'/><use href='#c9chn' transform='matrix(-12.3 -20.6 20.6 -12.3 240.3 48)'/><use href='#c9chn' transform='matrix(-3.4 -23.8 23.8 -3.4 288 96)'/><use href='#c9chn' transform='matrix(6.6 -23 23 6.6 288 168)'/><use href='#c9chn' transform='matrix(15 -18.7 18.7 15 240 216)'/>";
    bytes constant flg_ger = "<path fill='#fc0' d='M0 320h640v160H0z'/><path d='M0 0h640v160H0z'/><path fill='#d00' d='M0 160h640v160H0z'/>";
    bytes constant flg_ind = "<path fill='#e01' d='M0 0h640v249H0z'/><path fill='#fff' d='M0 240h640v240H0z'/>";
    bytes constant flg_kor = "<defs><clipPath id='c9kor1'><path fill-opacity='.7' d='M-95.8-.4h682.7v512H-95.8z'/></clipPath></defs><g fill-rule='evenodd' clip-path='url(#c9kor1)' transform='translate(89.8 .4) scale(.94)'><path fill='#fff' d='M-95.8-.4H587v512H-95.8Z'/><g transform='rotate(-56.3 361.6 -101.3) scale(10.67)'><g id='c9kor2'><path id='c9kor3' d='M-6-26H6v2H-6Zm0 3H6v2H-6Zm0 3H6v2H-6Z'/><use href='#c9kor3' y='44'/></g><path stroke='#fff' d='M0 17v10'/><path fill='#c33' d='M0-12a12 12 0 0 1 0 24Z'/><path fill='#04a' d='M0-12a12 12 0 0 0 0 24A6 6 0 0 0 0 0Z'/><circle cy='-6' r='6' fill='#c33'/></g><g transform='rotate(-123.7 191.2 62.2) scale(10.67)'><use href='#c9kor2'/><path stroke='#fff' d='M0-23.5v3M0 17v3.5m0 3v3'/></g></g>";
    bytes constant flg_uk  = "<path fill='#026' d='M0 0h640v480H0z'/><path fill='#fff' d='m75 0 244 181L562 0h78v62L400 241l240 178v61h-80L320 301 81 480H0v-60l239-178L0 64V0h75z'/><path fill='#c12' d='m424 281 216 159v40L369 281h55zm-184 20 6 35L54 480H0l240-179zM640 0v3L391 191l2-44L590 0h50zM0 0l239 176h-60L0 42V0z'/><path fill='#fff' d='M241 0v480h160V0H241zM0 160v160h640V160H0z'/><path fill='#c12' d='M0 193v96h640v-96H0zM273 0v480h96V0h-96z'/>";
    bytes constant flg_us  = "<path fill='#fff' d='M0 0h640v480H0z'/><g id='c9uss'><path fill='#fff' d='m30.4 11 3.4 10.3h10.6l-8.6 6.3 3.3 10.3-8.7-6.4-8.6 6.3L25 27.6l-8.7-6.3h10.9z'/></g><g id='c9uso'><use href='#c9uss'/><use href='#c9uss' y='51.7'/><use href='#c9uss' y='103.4'/><use href='#c9uss' y='155.1'/><use href='#c9uss' y='206.8'/></g><g id='c9use'><use href='#c9uss' y='25.9'/><use href='#c9uss' y='77.6'/><use href='#c9uss' y='129.5'/><use href='#c9uss' y='181.4'/></g><g id='c9usa'><use href='#c9uso'/><use href='#c9use' x='30.4'/></g><path fill='#b02' d='M0 0h640v37H0zm0 73.9h640v37H0zm0 73.8h640v37H0zm0 73.8h640v37H0zm0 74h640v36.8H0zm0 73.7h640v37H0zM0 443h640V480H0z'/><path fill='#026' d='M0 0h364.8v259H0z'/><use href='#c9usa'/><use href='#c9usa' x='60.8'/><use href='#c9usa' x='121.6'/><use href='#c9usa' x='182.4'/><use href='#c9usa' x='243.2'/><use href='#c9uso' x='304'/>";
    mapping(bytes1 => bytes2) stonum2;
    mapping(bytes1 => bytes5) stonum5;

    /**
     * @dev Sets up the mapping for compressed/mapped SVG input data.
     */
    constructor () {
        stonum2[0x61] = 0x2e35; // a->.5
        stonum2[0x41] = 0x3130; // A->10
        stonum2[0x42] = 0x3131; // B->11
        stonum2[0x43] = 0x3132; // C->12
        stonum2[0x44] = 0x3133; // D->13
        stonum2[0x45] = 0x3134; // E->14
        stonum2[0x46] = 0x3135; // F->15
        stonum2[0x47] = 0x3136; // G->16
        stonum2[0x48] = 0x3138; // H->18
        stonum2[0x49] = 0x3338; // I->38
        stonum5[0x55] = 0x322e363730; // U->2.670
        stonum5[0x56] = 0x342e353030; // V->4.500
        stonum5[0x57] = 0x352e353030; // W->5.500
        stonum5[0x58] = 0x372e353030; // X->7.500
        stonum5[0x59] = 0x32332e3333; // Y->23.33
        stonum5[0x5a] = 0x33322e3530; // Z->32.50
    }

    /**
     * @dev Adds the bytes32 + bytes8 representation of the address into the 
     * SVG output memory.
     */
    function addAddress(address _address, bytes memory b) internal pure {
        (bytes32 _a1, bytes8 _a2) = Helpers.addressToB32B8(_address);
        assembly {
            mstore(add(b, 2815), _a1)
            let dst := add(b, 2847)
            mstore(dst, or(and(mload(dst), not(shl(192, 0xFFFFFFFFFFFFFFFF))), _a2))
        }
    }

    /**
     * @dev Adds the `_id` into the SVG output memory `b`. 
     * Note: this is done so that multiple 
     * SVGs may be displayed on the same page without CSS conflict.
     */
    function addIds(bytes6 _id, bytes memory b) internal pure {
        uint16[11] memory offsets = [209, 235, 261, 303, 378, 809, 2287, 2365, 2559, 2916, 2978];
        uint16 idx;
        for(uint8 j; j<11; j++) {
            idx = offsets[j];
            assembly {
                let dst := add(b, idx)
                mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
            }
        }
    }

    /**
     * @dev Adds validity flag info to SVG output memory `b`.
     */
    function addValidityInfo(TokenInfo calldata _token, bytes memory b) internal view {
        uint8 _validityIdx = _token.validity;
        bytes16 _validity = "                ";
        if (_validityIdx > 0) {
            _validity = _vValidity[_validityIdx-1];
        }
        bytes3 _clr = bytes3("b00");
        bytes2 _in = bytes2("IN");
        bytes2 _marks = bytes2(">>");
        if (_validityIdx == 1) {
            _clr = bytes3("a0f");
            _in = bytes2("  ");
        }
        assembly {
            let _vcheck := gt(_validityIdx, 0)
            switch _vcheck case 1 {
                let dst := add(b, 2427)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _clr))
                dst := add(b, 2432)
                mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _in))
                dst := add(b, 2440)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _marks))
                dst := add(b, 2443)
                mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _validity))
            }
        }
    }

    /*
     * @dev Adds the `_token` information of fixed sized fields to hardcoded 
     * bytes `b`.
     */
    function addTokenInfo(TokenInfo calldata _token, bytes memory b) internal view {
        bytes7 _tagtxt = genTagsToAscii(_token.gentag, _token.tag);
        bytes7 _tushtxt = genTagsToAscii(_token.gentush, _token.tush);
        (bytes3 _rgc2, bytes16 _classer) = getGradientColors(_token);
        bytes6 _periods = getNFTAge(_token.mintstamp);
        bytes4 __mintid = Helpers.flip4Space(bytes4(Helpers.uintToBytes(_token.mintid)));
        bytes4 _royalty = Helpers.bpsToPercent(_token.royalty);
        bytes2 _edition = Helpers.flip2Space(Helpers.remove2Null(bytes2(Helpers.uintToBytes(_token.edition))));
        bytes2 _namesize = getNameSize(uint8(bytes(_token.name).length));

        assembly {
            // Name Font Size
            let dst := add(b, 278)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _namesize))
            // Colors
            dst := add(b, 511)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _rgc2))
            dst := add(b, 2632)
            mstore(dst, or(and(mload(dst), not(shl(128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))), _classer))
            // Edition
            let _edcheck := gt(_edition, 9)
            switch _edcheck case 0 {
                dst := add(b, 2701)
            } default {
                dst := add(b, 2700)
            }
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _edition))
            // Mintid
            dst := add(b, 2703)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintid))
            // Royalty
            dst := add(b, 2498)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _royalty))
            // Timestamps
            dst := add(b, 2736)
            let mask := shl(208, 0xFFFF00000000)
            let srcpart := and(_periods, mask)
            let destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 2739)
            mask := shl(208, 0x0000FFFF0000)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            dst := add(b, 2742)
            mask := shl(208, 0x00000000FFFF)
            srcpart := and(_periods, mask)
            destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
            // Gen Country Text
            dst := add(b, 2924)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), _tagtxt))
            dst := add(b, 2934)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), _tushtxt))
        }
    }

    /** 
     * @dev The Korea4L and embroidered tush tags have a marker added that 
     * differentiates their display versus standard Korea5L and Canadian tush 
     * tags. The provides the user with the information necessary to know 
     * what type of tag is present based on the SVG display alone.
     */
    function addTushMarker(uint8 _markertush) internal view returns (bytes memory e) {
        e = "<g transform='translate(532 708)' style='opacity:0.9; font-family:Tahoma; font-size:14;'><rect width='46' height='20' fill='#111' rx='5'/><text x='23' y='15' text-anchor='middle' fill='#ded'>    </text></g>";
        bytes4 x = _vMarkers[_markertush-1];
        assembly {
            let dst := add(e, 223)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), x))
        }
    }

    /**
     * @dev The SVG output memory `b` is finished off with the variable sized parts of `_token`.
     * This is a bit messy but bytes concat seems to get the job done.
     */
    function addVariableBytes(TokenInfo calldata _token, bytes6 _id) internal view returns(bytes memory vb) {
        bytes memory href = "<a href='https://collect9.io/nft/XXXXXX' target='_blank'>";
        assembly {
            let dst := add(href, 65)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
        }
        bytes memory gbarcode = "</a></g><g transform='translate(XXX 646) scale(0.33)'>";
        bytes3 x = _id[0] != 0x30 ? bytes3("385") : bytes3("400");
        assembly {
            let dst := add(gbarcode, 64)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), x))
        }
        
        vb = bytes.concat(
            bytes(_token.name),
            "</text></g><g transform='translate(20 621) scale(0.17)'>",
            getSVGFlag(_token.tag),
            "</g><g transform='translate(501 621) scale(0.17)'>",
            getSVGFlag(_token.tush),
            "</g><g transform='translate(157.5 146) scale(0.5)'>",
            href,
            qrCodeSVGFull(bytes(_token.qrdata)),
            gbarcode,
            href,
            barCodeSVG(bytes(_token.bardata), _id),
            "</a></g>"
        );
    }

    /**
     * @dev Reconstructs mapped compressed representation `_data` into a barcode SVG.
     */
    function barCodeSVG(bytes calldata _data, bytes6 _id) internal view returns(bytes memory output) {
        output = "<svg version='1.1' class='qr' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 264 100'><g transform='scale(3 100)'><rect x='13'/><rect x='21'/>";
        bytes memory entry = "     ";
        bytes memory tmp;
        bytes1 e0;
        bytes2 m2;
        bytes5 m5;
        uint8 j = 0;
        bool delims = false;
        uint l = 0;
        for(uint16 i; i<_data.length+l; i++) {
            if(!delims && j < 2) {
                entry[j] = _data[i-l];
                j += 1;
                continue;
            }
            if (delims && _data[i-l] != 0x3a) {
                entry[j] = _data[i-l];
                j += 1;
                if (i<_data.length+l-1) {
                    continue;
                }
            }

            j = 0;
            e0 = entry[0];
            if (e0 == 0x67) {
                delims = true;
                tmp = "</g><g transform='scale(X 100)'>";
                e0 = entry[1];
                assembly {
                    let dst := add(tmp, 56)
                    mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e0))
                }
                output = bytes.concat(output, tmp);
                if (e0 == 0x36) {
                    output = bytes.concat(output, "<rect x='5'/>");
                }
                if (e0 == 0x39) {
                    output = bytes.concat(output, "<rect x='5.33'/>");
                }
            } 
            else {
                m2 = stonum2[e0];
                if (m2 != 0x0000) {
                    output = bytes.concat(output, "<rect x='", m2, "'/>");
                }
                else {
                    m5 = stonum5[e0];
                    output = m5 != 0x0000000000 ? bytes.concat(output, "<rect x='", m5, "'/>") : bytes.concat(output, "<rect x='", Helpers.concatTilSpace(entry, 0), "'/>");
                }
                if (!delims) {
                    l += 1;
                }
            }
            entry = "     ";
        }
        // Remainder of the barcode svg
        tmp = "</g><text x='132' y='126' text-anchor='middle' font-family='Helvetica' font-size='28' fill='#111'>* XXXXXX  *</text></svg>";
        if (_id[0] != 0x30) {
            tmp[100] = 0x30;
            j = 1;
        }
        assembly {
            let dst := add(add(tmp, 132), j)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
        }
        output = bytes.concat(output, tmp);
    }

    /**
     * @dev Ghost tiers get a little more fun. They get a nebula-like background 
     * that's one of 4 color templates chosen pseudo-random to the viewer 
     * at each call. OpenSea, Rarible etc. will cache one at random, 
     * but users should be able to fetch meta-data updates to see 
     * color changes.
     */
    function checkForSpecialBg(uint8 _rtier, bytes memory b) internal view {
        bytes32 _filter_mod = "turbulence' baseFrequency='0.002";
        bytes3 _feMatrix_mod = bytes3("0.9");
        bytes32[3] memory mods = [bytes32("1 1 0 0 0 1 0 0 0 0 0 1 0 0 0 0 "),
            "0 0 0 0 1 1 0 0 0 0 0 1 0 0 0 0 ",
            "0 0 0 0 0 1 0 0 0 0 0 1 1 1 0 0 "];
        if (_rtier == 8) {
            assembly {
                let dst := add(b, 574)
                mstore(dst, _filter_mod)
                dst := add(b, 620)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "4"))
                dst := add(b, 731)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _feMatrix_mod))
            }
            uint256 psrand = block.timestamp % 4;
            if (psrand < 4) {
                bytes32 _colormod = mods[psrand];
                assembly {
                    let dst := add(b, 697)
                    mstore(dst, _colormod)
                }
            }
        }
    }

    /**
     * @dev Converts integer inputs to the ordinal country ascii text representation 
     * based on input params `_gentag` and `_tag`.
     */
    function genTagsToAscii(uint8 _gentag, uint8 _tag) internal view returns(bytes7) {
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
     * @dev Returns styling and textual information based on token attributes input 
     * params `_spec` and `_rtier`.
     */
    function getGradientColors(TokenInfo calldata _token) internal view returns (bytes3, bytes16) {
        uint8 _spec = _token.spec;
        uint8 _rtier = _token.rtier;
        bytes3[11] memory spec_c2 = [bytes3("101"), "fc3", "bbb", "a74", "c0f", "c00", "0a0", "0cf", "eee", "cb8", "fff"];
        return (spec_c2[_spec], rtiers[_rtier]);
    }

    /**
     * @dev Since SVG text does not automatically contain itself to bounds, 
     * this function returns the font size of text depending on input `len` 
     * so that it stays contained.
     */
    function getNameSize(uint8 len) internal pure returns(bytes2) {
        if (len < 11) {
            return "52";
        }
        else if (len > 17) {
            return "30";
        }
        else {
            uint8 adjuster = (len-10)*3;
            uint8 fontsize = 52 - adjuster;
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
    function getNFTAge(uint256 _mintstamp) internal view returns(bytes6) {
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
     * @dev Gets the hardcoded SVG flag depending on input `_flag`. 
     * If input is not within a valid range (<7), then return a blank 
     * flag will be returned.
     */
    function getSVGFlag(uint8 _flag) internal pure returns(bytes memory) {
        if (_flag == 0) {
            return flg_can;
        }
        else if (_flag == 1) {
            return flg_chn;
        }
        else if (_flag == 2) {
            return flg_ger;
        }
        else if (_flag == 3) {
            return flg_ind;
        }
        else if (_flag == 4) {
            return flg_kor;
        }
        else if (_flag == 5) {
            return flg_uk;
        }
        else if (_flag == 6) {
            return flg_us;
        }
        else {
            return flg_blk;
        }
    }

    /**
     * @dev Reconstructs mapped compressed representation of data into a 
     * micro QRCode SVG from input `_data`.
     */
    function qrCodeSVG(bytes memory _data) internal view returns(bytes memory output) {
        bytes memory entry = "      ";
        bytes memory tmp;
        bytes1 e0;
        bytes2 m2;
        bytes3[3] memory colors = [bytes3("111"), "007", "407"];
        bytes3 color;

        bool delims = false;
        bool xflg = false;
        bool yflg = false;
        uint8 j = 0;
        uint8 k = 1;
        uint8 l = 0;
        for(uint16 i; i<_data.length-2; i++) {
            if(!delims) {
                entry[j] = _data[i+l];
            }
            if (delims && _data[i+l] != 0x3a) {
                entry[j] = _data[i+l];
                j += 1;
                if (i<_data.length-3) {
                    continue;
                }
            }

            j = 0;
            e0 = entry[0];
            m2 = stonum2[e0];
            bytes5 m5 = stonum5[e0];
            if (xflg) {
                if (m2 != 0x0000) {
                    output = bytes.concat(output, "x='", m2, "'");
                }
                else {
                    output = m5 != 0x0000000000 ? bytes.concat(output, "x='", m5, "'") : bytes.concat(output, "x='", Helpers.concatTilSpace(entry, 0), "'");
                }
                xflg = false;
                yflg = true;
            }
            else if (yflg) {
                tmp = "' fill='#XXX'/>";
                color = colors[i % 3];
                assembly {
                    let dst := add(tmp, 41)
                    mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), color))
                }
                if (m2 != 0x0000) {
                    output = bytes.concat(output, " y='", m2, tmp);
                }
                else {
                    output = m5 != 0x0000000000 ? bytes.concat(output, " y='", m5, tmp) : bytes.concat(output, " y='", Helpers.concatTilSpace(entry, 0), tmp);
                } 
                yflg = false;
            }
            else {
                if (e0 == 0x65) {
                    output = bytes.concat(output, "</g>");
                    entry = "      ";
                    continue;
                }
                else if (e0 == 0x67) {
                    delims = true;
                    l = 2;
                    tmp = "<g transform='scale(X 1)'>";
                    e0 = _data[i+1];
                    assembly {
                        let dst := add(tmp, 52)
                        mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e0))
                    }
                    output = bytes.concat(output, tmp);
                    entry = "      ";
                    continue;
                }
                else if (e0 == 0x77) {
                    tmp = "<rect style='width: px;' ";
                    e0 = entry[1];
                    assembly {
                        let dst := add(tmp, 51)
                        mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e0))
                    }
                    output = bytes.concat(output, tmp);
                    xflg = true;
                    entry = "      ";
                    continue;
                }
                else if (e0 == 0x64) {
                    output = bytes.concat(output, "<use href='#d' ");
                    if(!delims) {
                        xflg = true;
                        entry = "      ";
                        continue;
                    }
                }
                else if (e0 == 0x6a) {
                    output = bytes.concat(output, "<use href='#j' ");
                    if(!delims) {
                        xflg = true;
                        entry = "      ";
                        continue;
                    }
                }
                else {
                    output = bytes.concat(output, '<rect ');
                    k = 0;
                }

                e0 = entry[k];
                m2 = stonum2[e0];
                if (m2 != 0x0000) {
                    output = bytes.concat(output, "x='", m2, "'");
                }
                else {
                    m5 = stonum5[e0];
                    output = m5 != 0x0000000000 ? bytes.concat(output, "x='", m5, "'") : bytes.concat(output, "x='", Helpers.concatTilSpace(entry, k), "'");
                }          
                k = 1;
                yflg = true;
            }
            entry = "      ";
        }
    }

    /**
     * @dev Constructs the SVG XML/HTML code from the fixed (hardcoded) and input `_qrdata`.
     */
    function qrCodeSVGFull(bytes calldata _qrdata) internal view returns (bytes memory) {
        return bytes.concat(
            "<svg version='1.1' class='qr' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 17 17'><style type='text/css'>.qr{opacity:0.89;} .qr rect{width:1px;height:1px;}</style><symbol id='d'><rect height='1' width='1'/><rect x='2' height='1' width='1'/></symbol><symbol id='j'><rect height='1' width='1'/><rect x='3' height='1' width='1'/></symbol><rect transform='scale(3)' x='0.67' y='0.67' fill='#111'/><rect x='0.5' y='0.5' style='width:6px;height:6px;fill:none;stroke:#111;'/>",
            qrCodeSVG("d80dC0G0G1dB3F4dD5F6B7d08d58C8F90AFA0CGC0EBF0Gg2:W:4:V:6:X:7:V:8:X:8:6.5:B:W:C:W:G:e:"),
            qrCodeSVG(_qrdata),
            "</svg>"
        );
    }

    /**
     * @dev External function to call and return the SVG string built from `_token`  
     * and owner `_address`.
     */
    function returnSVG(address _address, TokenInfo calldata _token) external view override returns (string memory) {
        bytes memory b = "<svg version='1.1' class='c9svg' xmlns='http://www.w3.org/2000/svg' width='100%' height='100%' viewBox='0 0 630 880'><style type='text/css'>.c9svg{font-family:'Courier New';} .sXXXXXX{font-size:22px;} .mXXXXXX{font-size:32px;} .tXXXXXX{font-size:54px;font-weight:700;} .nXXXXXX{font-size:34px;font-weight:700;}</style><defs><radialGradient id='rgXXXXXX' cx='50%' cy='44%' r='50%' gradientUnits='userSpaceOnUse'><stop offset='25%' stop-color='#fff'/><stop offset='1' stop-color='#e66'/></radialGradient><filter id='noiser'><feTurbulence type='fractalNoise' baseFrequency='0.2' numOctaves='8'/><feComposite in2='SourceGraphic' operator='in'/><feColorMatrix values='1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0 0 0.2 0'/></filter></defs><rect rx='20' width='100%' height='100%' fill='url(#rgXXXXXX)'/><rect width='100%' height='100%' rx='20' filter='url(#noiser)'/><rect y='560' width='100%' height='22' fill='#ddf' fill-opacity='0.6'/><g style='fill:#ded;'><rect x='20' y='20' width='590' height='150' rx='10'/><rect x='20' y='740' width='590' height='120' rx='10'/></g><g transform='translate(470 6) scale(0.2)' fill-opacity='0.89'><a href='https://collect9.io' target='_blank'><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 256 276'><defs><radialGradient id='c9r1' cx='50%' cy='50%' r='50%' gradientUnits='userSpaceOnUse'><stop offset='25%' stop-color='#2fd'/><stop offset='1' stop-color='#0a6'/></radialGradient><radialGradient id='c9r2' cx='50%' cy='50%' r='50%' gradientUnits='userSpaceOnUse'><stop offset='25%' stop-color='#26f'/><stop offset='1' stop-color='#03a'/></radialGradient><radialGradient id='c9r3' cx='50%' cy='50%' r='50%' gradientUnits='userSpaceOnUse'><stop offset='25%' stop-color='#2ff'/><stop offset='1' stop-color='#0a9'/></radialGradient></defs><symbol id='c9p'><path d='M122.4,2,26,57.5a11,11,0,0,0,0,19.4h0a11,11,0,0,0,11,0l84-48.5V67L74.3,94.3a6,6,0,0,0,0,10L125,134a6,6,0,0,0,6,0l98.7-57a11,11,0,0,0,0-19.4L133.6,2A11,11,0,0,0,122.4,2Zm12,65V28.5l76,44-33.5,19.3Z'/></symbol><use href='#c9p' fill='url(#c9r2)'/><use href='#c9p' transform='translate(0 9.3) rotate(240 125 138)' fill='url(#c9r3)'/><use href='#c9p' transform='translate(9 4) rotate(120 125 138)' fill='url(#c9r1)'/></svg></a></g><g transform='translate(30 58)' class='mXXXXXX'><text>COLLECT9</text><text y='34'>RWA REDEEMABLE NFT</text><g class='sXXXXXX'><text y='74'>STATUS: <tspan font-weight='bold' fill='#080'>  VALID                    </tspan></text><text y='100'>EIP-2981: 3.50%</text></g></g><g transform='translate(30 768)' class='sXXXXXX'><text>CLASS: VINTAGE BEANIE BABY</text><text y='26'>RARITY TIER:                                 </text><text y='52'>ED NUM.MINT ID:   .    </text><text y='78'>NFT AGE:   YR   MO   D</text></g><text x='50%' y='576' fill='#999' text-anchor='middle'>a2a3c5f0f4ce432893d0beafc2f5b32607e68bb0</text><g text-anchor='middle'><text x='50%' y='645' class='nXXXXXX'>        |        </text><text x='50%' y='698' class='tXXXXXX'>";
        bytes6 _id = Helpers.tokenIdToBytes(_token.id);
        addIds(_id, b);
        addTokenInfo(_token, b);
        addValidityInfo(_token, b);
        addAddress(_address, b);
        checkForSpecialBg(_token.rtier, b);
        bytes memory e;
        if (_token.markertush > 0) {
            e = addTushMarker(_token.markertush);
        }
        return string(bytes.concat(b, addVariableBytes(_token, _id), e, "</svg>"));
    }
}