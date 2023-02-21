// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

library Helpers {
    function addressToB32B8(address x)
        internal pure
        returns(bytes32 _a1, bytes8 _a2) {
            bytes memory _address = toAsciiString(x);
            assembly {
                _a1 := mload(add(_address, 32))
                _a2 := mload(add(_address, 64))
            }
    }

    function bpsToPercent(uint256 input)
        internal pure
        returns(bytes4) {
            bytes32 _input = uintToBytes(input);
            bytes memory tmp = "X.XX";
            bytes1 e0 = _input[0];
            bytes1 e1 = _input[1];
            bytes1 e2 = _input[2];
            assembly {
                let dst := add(tmp, 32)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e0))
                dst := add(tmp, 34)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e1))
                dst := add(tmp, 35)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), e2))
            }
            return bytes4(tmp);
    }

    // https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    function char(bytes1 b)
        internal pure
        returns (bytes1 c) {
            return (uint8(b) < 10) ? bytes1(uint8(b) + 0x30) : bytes1(uint8(b) + 0x57);
    }

    function concatTilSpace(bytes memory entry, uint256 offset)
        internal pure
        returns(bytes memory output) {
            bytes1 e0;
            for (uint256 j; j<entry.length; j++) {
                e0 = entry[j+offset];
                if (e0 == 0x20) { //space
                    break;
                }
                output = bytes.concat(output, e0);
            }
    }

    function flipSpace(bytes memory input, uint256 o0)
        internal pure {
            uint256 o1 = 1+o0;
            if (input[o1] == 0x00) {
                input[o1] = input[o0];
                input[o0] = 0x20;
            }
    }

    function flip2Space(bytes2 input)
        internal pure
        returns (bytes2) {
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

    function flip4Space(bytes4 input)
        internal pure
        returns (bytes4) {
            bytes memory output = new bytes(4);
            for (uint256 i; i<4; i++) {
                if (input[i] == 0x00) {
                    output[i] = 0x20;
                }
                else {
                    output[i] = input[i];
                }
            }
            return bytes4(output);
    }

    //https://ethereum.stackexchange.com/questions/126899/convert-bytes-to-hexadecimal-string-in-solidity
    function iToHex(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }
        return string(abi.encodePacked("0x", converted));
    }

    function _quick(uint256[] memory data, uint256 low, uint256 high)
        private pure {
            if (low < high) {
                uint256 pivotVal = data[(low + high) / 2];
                uint256 low1 = low;
                uint256 high1 = high;
                for (;;) {
                    while (data[low1] < pivotVal) {
                        ++low1;
                    }
                    while (data[high1] > pivotVal) {
                        --high1;
                    }
                    if (low1 >= high1) {
                        break;
                    }
                    (data[low1], data[high1]) = (data[high1], data[low1]);
                    ++low1;
                    --high1;
                }
                if (low < high1) {
                    _quick(data, low, high1);
                }
                ++high1;
                if (high1 < high) {
                    _quick(data, high1, high);
                }
            }
    }

    function quickSort(uint256[] calldata data)
        internal pure 
        returns (uint256[] memory sorted) {
            sorted = data;
            if (sorted.length > 1) {
                _quick(sorted, 0, sorted.length - 1);
            }
    }

    function remove2Null(bytes2 input)
        internal pure
        returns (bytes2) {
            bytes memory output = new bytes(2);
            for (uint256 i; i<2; i++) {
                if (input[i] == 0x00) {
                    output[i] = 0x20;
                }
                else {
                    output[i] = input[i];
                }
            }
            return bytes2(output);
    }

    function stringEqual(string memory _a, string memory _b)
        internal pure
        returns (bool) {
            return keccak256(bytes(_a)) == keccak256(bytes(_b));
    }

    function strToUint(string memory _str)
        internal pure
        returns (uint256 res, bool err) {
        for (uint256 i; i<bytes(_str).length;) {
            if ((uint8(bytes(_str)[i]) - 48) < 0 || (uint8(bytes(_str)[i]) - 48) > 9) {
                return (0, false);
            }
            res += (uint8(bytes(_str)[i]) - 48) * 10**(bytes(_str).length - i - 1);
            unchecked {++i;}
        }
        return (res, true);
    }

    // https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    function toAsciiString(address x)
        internal pure
        returns (bytes memory) {
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

    function tokenIdToBytes(uint256 _id)
        internal pure
        returns (bytes6) {
            bytes memory output = new bytes(6);
            output[0] = bytes1("0");
            bytes32 _bid = uintToBytes(_id);
            uint256 _offset = _bid[5] == 0x00 ? 1 : 0;
            for (uint256 j=0; j<6-_offset; j++) {
                output[j+_offset] = _bid[j];
            }
            return bytes6(output);
    }

    function uintToBool(uint256 v)
        internal pure
        returns(bool) {
            return v == 1 ? true : false;
    }

    // https://ethereum.stackexchange.com/questions/6591/conversion-of-uint-to-string
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

    function uintToOrdinal(uint256 _input)
        internal pure
        returns (bytes3) {
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
                    bytes.concat(
                        bytes1(uintToBytes(_input)),
                        "TH"
                    )
                );
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