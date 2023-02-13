// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
//import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IC9Token.sol";
import "./abstract/C9Errors.sol";
import "./utils/Helpers.sol";

contract C9GameSVG {
    //using Strings for uint256;

    address public immutable contractToken;

    constructor(address _contractToken) {
        contractToken = _contractToken;
    }

    function addressToRGB(address _address)
        private pure
        returns (uint256, uint256, uint256) {
            uint256 _addressToUint = uint256(uint160(_address));
            uint256 _addressKeccaked = uint256(keccak256(abi.encodePacked(_address)));

            uint256 _red = uint256(uint8(_addressToUint));
            uint256 _green = uint256(uint8(_addressKeccaked));
            uint256 _blue = uint256(uint8(_red+_green));

            return (_red, _green, _blue);
    }

    

    function b32Culled(bytes32 _b32, uint256 limit)
        internal pure
        returns (string memory) {
            uint256 _len;
            for(uint256 i; i<limit;) {
                if (_b32[i] == 0x00) {
                    _len = i;
                    break;
                }
                unchecked {++i;}
            }
            bytes memory output = new bytes(_len);
            for(uint256 i; i<_len;) {
                output[i] = _b32[i];
                unchecked {++i;}
            }
            return string(output);
        }

    function _rgb(string memory output, uint256 color, uint256 offset)
    private pure {
        bytes3 _color = bytes3(Helpers.uintToBytes(color));
        assembly {
            let dst := add(output, offset)
            let mask := shl(232, 0xFFFFFF)
            let cond := lt(color, 10)
            switch cond case true {
                dst := add(dst, 2)
                mask := shl(248, 0xFF)
            }
            default {
                let cond2 := lt(color, 100)
                switch cond2 case true {
                    dst := add(dst, 1)
                    mask := shl(240, 0xFFFF)
                }
            }
            let srcpart := and(_color, mask)
            let destpart := and(mload(dst), not(mask))
            mstore(dst, or(destpart, srcpart))
        }
    }

    function _coor(string memory output, uint256 xy, uint256 offset)
    private pure {
        bytes2 _xy = bytes2(Helpers.uintToBytes(xy));
        assembly {
            if gt(xy, 0) {
                let dst := add(output, offset)
                let mask := shl(240, 0xFFFF)
                let cond := lt(xy, 10)
                switch cond case true {
                    dst := add(dst, 1)
                    mask := shl(248, 0xFF)
                }
                let srcpart := and(_xy, mask)
                let destpart := and(mload(dst), not(mask))
                mstore(dst, or(destpart, srcpart))
            }
        }
    }

    function _label(string memory output, address tokenOwner)
    private pure {
        bytes memory _bAddress = Helpers.toAsciiString(tokenOwner);
        bytes2 _b2Address = bytes2(_bAddress);
        assembly {
            let dst := add(output, 140)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _b2Address))
        }
    }

    function rect(address tokenOwner, uint256 x, uint256 y, uint256 r, uint256 g, uint256 b)
        private pure
        returns (string memory output) {
            // Output of the rect element
            output = ''
                '<use href="#r" x="00" y="00" fill="rgb(000,000,000)"/>'
                '<text x="00" y="00" class="c9gn" text-anchor="middle">0x</text>';

            // Rect position and color
            _coor(output, x, 50);
            _coor(output, y, 57);
            _rgb(output, r, 71);
            _rgb(output, g, 75);
            _rgb(output, b, 79);

            // Text position and label
            _coor(output, x+5, 95);
            _coor(output, y+7, 102);
            _label(output, tokenOwner);
    }

    function buildRects(uint256 _gameSize)
        external view 
        returns (string memory output) {
            uint256 x;
            uint256 y;
            uint256 z;
            uint256 r;
            uint256 g;
            uint256 b;
            uint256 _tokenId;
            address _tokenOwner;
            for (uint256 i; i<_gameSize;) {
                y = 0;
                for(uint256 j; j<_gameSize;) {
                    z = j*_gameSize + x;
                    _tokenId = IC9Token(contractToken).tokenByIndex(z);
                    _tokenOwner = IC9Token(contractToken).ownerOf(_tokenId);
                    (r, g, b) = addressToRGB(_tokenOwner);
                    output = string.concat(output, rect(_tokenOwner, x, y, r, g, b));
                    unchecked {
                        y+=10;
                        ++j;
                    }
                }
                unchecked {
                    x+=10;    
                    ++i;
                }
            }
    }


}