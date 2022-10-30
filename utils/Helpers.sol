// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

library Helpers {
    function addressToB32B8(address x) internal pure returns(bytes32 _a1, bytes8 _a2) {
        bytes memory _address = toAsciiString(x);
        assembly {
            _a1 := mload(add(_address, 32))
            _a2 := mload(add(_address, 64))
        }
    }

    function bpsToPercent(uint96 input) internal pure returns(bytes3) {
        bytes32 _input = uintToBytes(input);
        bytes memory tmp = "X.X";
        bytes1 e0 = _input[0];
        bytes1 e1 = _input[1];
        assembly {
            let dst := add(tmp, 32)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e0))
            dst := add(tmp, 34)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e1))
        }
        return bytes3(tmp);
    }

    // https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function checkTagForNulls(bytes3 __cntrytag) internal pure returns (bytes3) {
        /*
        Needed for tag countries that are only 2-letter abbreviations otherwise a 
        special character shows up in the base64 decode due to the null byte. This 
        is also to keep consistent with what the authentication labels show (i.e. 
        UK instead of GBR).
        */
        bytes memory _tmpcntrytag = new bytes(3);
        assembly {
            let dst := add(_tmpcntrytag, 32)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), __cntrytag))
        }
        if (_tmpcntrytag[2] == 0x00) {
           _tmpcntrytag[2] = 0x20; 
        }
        return bytes3(_tmpcntrytag);
    }

    function concatTilSpace(bytes memory entry, uint8 offset) internal pure returns(bytes memory output) {
        bytes1 e0;
        for (uint8 j; j<entry.length; j++) {
            e0 = entry[j+offset];
            if (e0 == 0x20) { //space
                break;
            }

            if (e0 == 0x5a) { //Z
                output = bytes.concat(output, ".5");
            }
            else if (e0 == 0x59) { //Y
                output = bytes.concat(output, ".33");
            }
            else if (e0 == 0x58) { //X
                output = bytes.concat(output, ".67");
            }
            else {
                output = bytes.concat(output, e0);
            }
        }
    }

    function flipSpace(bytes memory input, uint8 o0) internal pure {
        uint8 o1 = 1+o0;
        if (input[o1] == 0x00) {
            input[o1] = input[o0];
            input[o0] = 0x20;
        }
    }

    function flip2Space(bytes2 input) internal pure returns (bytes2) {
        bytes memory output = new bytes(2);
        if (input[1] == 0x20) {
            output[0] = input[1];
            output[1] = input[0];
        }
        else {
            output[0] = input[0];
            output[1] = input[1];
        }
        return bytes2(output);
    }

    function flip4Space(bytes4 input) internal pure returns (bytes4) {
        bytes memory output = new bytes(4);
        for(uint8 i; i<4; i++) {
            if (input[i] == 0x00) {
                output[i] = 0x20;
            }
            else {
                output[i] = input[i];
            }
        }
        return bytes4(output);
    }

    function remove2Null(bytes2 input) internal pure returns (bytes2) {
        bytes memory output = new bytes(2);
        for(uint8 i; i<2; i++) {
            if (input[i] == 0x00) {
                output[i] = 0x20;
            }
            else {
                output[i] = input[i];
            }
        }
        return bytes2(output);
    }

    // https://ethereum.stackexchange.com/questions/62371/convert-a-string-to-a-uint256-with-error-handling
    function strToUint(string memory str_) internal pure returns (uint256 res, bool) {
        for (uint256 i; i < bytes(str_).length; i++) {
            if ((uint8(bytes(str_)[i]) - 48) < 0 || (uint8(bytes(str_)[i]) - 48) > 9) {
                return (0, false);
            }
            res += (uint8(bytes(str_)[i]) - 48) * 10**(bytes(str_).length - i - 1);
        }
        return (res, true);
    }

    // https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    function toAsciiString(address x) internal pure returns (bytes memory) {
        bytes memory s = new bytes(40);
        for (uint256 i; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return s;
    }

    function tokenIdToBytes(uint24 _id) internal pure returns (bytes6) {
        bytes memory output = new bytes(6);
        output[0] = bytes1("0");
        bytes32 _bid = uintToBytes(_id);
        uint8 _offset = _bid[5] == 0x00 ? 1 : 0;
        for (uint8 j=0; j<6-_offset; j++) {
            output[j+_offset] = _bid[j];
        }
        return bytes6(output);
    }

    // https://ethereum.stackexchange.com/questions/6591/conversion-of-uint-to-string
    function uintToBytes(uint256 v) internal pure returns (bytes32 ret) {
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

    function uintToOrdinal(uint8 _input) internal pure returns (bytes3) {
        if (_input == 0) {
            return "PRE";
        }
        if (_input == 254) {
            return "TYR";
        }
        if (_input == 255) {
            return "PAX";
        }
        bytes32[4] memory ends = [bytes32("TH"), "ST", "ND", "RD"];
        if(((_input % 100) >= 11) && ((_input % 100) <= 13)) {
            return bytes3(
                bytes.concat(bytes1(uintToBytes(_input)), "TH"));
        }
        else {
            return bytes3(
                bytes.concat(
                    bytes1(uintToBytes(_input)),
                    bytes2(ends[_input % 10])
                )
            );
        }
    }
}