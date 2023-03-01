// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
//import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IC9Game.sol";
import "./interfaces/IC9GameSVG.sol";
import "./interfaces/IC9Token.sol";
import "./abstract/C9Errors.sol";
import "./utils/Helpers.sol";

// Need to show PENDING for pending mints

contract C9GameSVG is IC9GameSVG {
    string constant SVG_HDR = ''
        '<svg class="c9O" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="100%" height="100%">'
        '<style>'
        '.c9O {font-family: "Poppins", sans-serif; font-weight:bold; fill:#333;}'
        '.c9I {filter: sepia(000%) saturate(100%);}'
        '.c9gE {font-size:34px; fill:#ee8;}'
        '.c9gT {font-size:14px; fill:#ded;}'
        '.c9gS {font-size:7px; fill:#ded;}'
        '</style>'
        '<svg class="c9I" xmlns="http://www.w3.org/2000/svg" width="100%" height="100%">'
        '<defs>'
        '<linearGradient id="c9gbg">'
        '<stop offset="0" stop-color="#C76CD7" />'
        '<stop offset="1" stop-color="#3123AE" />'
        '</linearGradient>'
        '</defs>'
        '<rect width="100%" height="100%" rx="8%" fill="url(#c9gbg)" />'
        '<text x="120" y="15" class="c9gT" text-anchor="middle">coLLect9 coNNectX</text>'
        '<text x="22" y="229" class="c9gS">Token ID = 0     </text>'
        '<text x="22" y="237" class="c9gS">View = XxX</text>'
        '<text x="120" y="229" class="c9gS" text-anchor="middle">View Max Win</text>'
        '<text x="120" y="237" class="c9gS" text-anchor="middle">ETH =  0.000</text>'
        '<text x="218" y="229" class="c9gS" text-anchor="end">Token rID = 0     </text>'
        '<text x="218" y="237" class="c9gS" text-anchor="end">Current rID = 0     </text>'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-005 -005 060 060" width="100%" height="100%">'
        '<defs>'
        '<symbol id="r">'
        '<rect width="10" height="10" style="cursor:pointer;"/>'
        '</symbol>'
        '</defs>'
        '<style>'
        '.c9gn {font-family:"Courier New"; font-size:5px; font-weight:bold; opacity:0.4;}'
        '.c9gnS {font-size:2.5px; opacity:0.9;}'
        '</style>';

    string constant SVG_FTR = ''
        '<rect x="0" y="0" width="00" height="00" style="stroke: #FA4; stroke-width: 1; fill: none;" />'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 276" height="000%" width="000%" x="30%" y="30%">'
        '<symbol id="a">'
        '<path d="M122.4,2,26.2,57.5a11,11,0,0,0,0,19.4h0a11.2,11,0,0,0,11,0l84-48.5V67L74.3,94.3a6,6,0,0,0,0,10L125,133.8a6,6,0,0,0,6,0l98.7-57a11,11,0,0,0,0-19.4L133.6,2A11,11,0,0,0,122.4,2Zm12.2,65V28.5l76,44-33.5,19.3Z"/>'
        '</symbol>'
        '<use href="#a"/>'
        '<use href="#a" transform="translate(0 9.3) rotate(240 125 138)"/>'
        '<use href="#a" transform="translate(9 4) rotate(120 125 138)"/>'
        '</svg></svg></svg>'
        '<text x="50%" y="55%" class="c9gE" text-anchor="middle">       </text>'
        '<text x="50%" y="57%" class="c9gS" text-anchor="middle">                                          </text>'
        '</svg>';

    mapping(uint256 => string) viewBoxMin;
    mapping(uint256 => string) viewBoxMax;
    mapping(uint256 => string) logoWidth;

    address public immutable contractToken;
    address public contractGame;

    constructor(address _contractGame, address _contractToken) {
        contractGame = _contractGame;
        contractToken = _contractToken;
        viewBoxMin[5] = "005";
        viewBoxMax[5] = "060";
        viewBoxMin[7] = "7.5";
        viewBoxMax[7] = "085";
        viewBoxMin[9] = "010";
        viewBoxMax[9] = "110";
        logoWidth[5] = "013";
        logoWidth[7] = "010";
        logoWidth[9] = "7.5";
    }

    function _addressToRGB(address _address)
    private pure
    returns (uint256, uint256, uint256) {
        uint256 _addressToUint = uint256(uint160(_address));
        uint256 _addressKeccak = uint256(keccak256(abi.encodePacked(_address)));

        uint256 _red = uint256(uint8(_addressToUint));
        uint256 _green = uint256(uint8(_addressKeccak));
        uint256 _blue = uint256(uint8(_red+_green));

        return (_red, _green, _blue);
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

    function _setHDR(bytes6 _tokenId, uint256 gameSize, bytes6 _tokenRoundId, bytes6 _currentRoundId, bool expired, bool priorWinner)
    private view
    returns (string memory) {
        string memory hdr = SVG_HDR;
        bytes1 _gameSize = bytes1(Helpers.uintToBytes(gameSize));
        bytes3 _viewBoxMin = bytes3(bytes(viewBoxMin[gameSize]));
        bytes3 _viewBoxMax = bytes3(bytes(viewBoxMax[gameSize]));
        (uint256 _pot1, uint256 _pot2) = IC9Game(contractGame).currentPotSplit(gameSize);
        bytes6 _gamePot = _viewPot((_pot1+_pot2));
        assembly {
            let dst := add(hdr, 764)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _tokenId))
            dst := add(hdr, 818)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _gameSize))
            dst := add(hdr, 820)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _gameSize))
            dst := add(hdr, 965)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _gamePot))
            dst := add(hdr, 1043)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _tokenRoundId))
            dst := add(hdr, 1123)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _currentRoundId))
            dst := add(hdr, 1186)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _viewBoxMin))
            dst := add(hdr, 1191)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _viewBoxMin))
            dst := add(hdr, 1195)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _viewBoxMax))
            dst := add(hdr, 1199)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _viewBoxMax))
        }
        if (expired) {
            assembly {
                let dst := add(hdr, 231)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "1"))
                dst := add(hdr, 246)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "0"))
            }
        }
        if (priorWinner) {
            assembly {
                let dst := add(hdr, 231)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "1"))
                dst := add(hdr, 246)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "3"))
            }
        }
        return hdr;   
    }

    function _viewPot(uint256 pot)
    private pure
    returns (bytes6) {
        bytes memory _sViewPot = " 0.000";
        uint256 _leadingDecimal = pot / 10**18;
        uint256 _trailingDecimal = (pot / 10**15) % 1000;
        bytes2 _bLeadingDecimal = bytes2(Helpers.sTokenId(_leadingDecimal));
        bytes3 _bTrailingDecimal = bytes3(Helpers.sTokenId(_trailingDecimal));

        assembly {
            let dst := add(_sViewPot, 33)
            // Leading decimal
            if gt(_leadingDecimal, 0) {
                if gt(_leadingDecimal, 9) {
                    dst := add(_sViewPot, 32)
                }
                mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _bLeadingDecimal))
            }
            // Trailing decimal
            dst := add(_sViewPot, 35)
            if lt(_trailingDecimal, 100) {
                dst := add(_sViewPot, 36)
                if lt(_trailingDecimal, 10) {
                    dst := add(_sViewPot, 37)
                }
            }
            mstore(dst, _bTrailingDecimal)
            // Put decimal point back in
            dst := add(_sViewPot, 34)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "."))
        }

        return bytes6(_sViewPot);
    }

    function _setFTR(uint256 gameSize, bool expired, address priorWinner)
    private view
    returns (string memory) {
        string memory ftr = SVG_FTR;
        uint256 _uLogoPos;
        uint256 _uGameWidth;
        unchecked {
            _uLogoPos = 5 + ((gameSize % 5) / 2);
            _uGameWidth = 10*gameSize;
        }
        bytes1 _logoPos = bytes1(Helpers.uintToBytes(_uLogoPos));
        bytes3 _logoWidth = bytes3(bytes(logoWidth[gameSize]));
        bytes2 _gameWidth = bytes2(Helpers.uintToBytes(_uGameWidth));
        assembly {
            let dst := add(ftr, 57)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _gameWidth))
            dst := add(ftr, 69)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _gameWidth))
            dst := add(ftr, 196)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _logoWidth))
            dst := add(ftr, 209)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _logoWidth))
            dst := add(ftr, 219)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _logoPos))
            dst := add(ftr, 227)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _logoPos))
        }
        if (expired) {
            assembly {
                let dst := add(ftr, 689)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), "EXPIRED"))
            }
        }
        if (priorWinner != address(0)) {
            (bytes32 _a1, bytes8 _a2) = Helpers.addressToB32B8(priorWinner);
            assembly {
                let dst := add(ftr, 651)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "3"))
                dst := add(ftr, 689)
                mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), "WINNER "))
                dst := add(ftr, 759)
                mstore(dst, _a1)
                dst := add(ftr, 791)
                mstore(dst, or(and(mload(dst), not(shl(192, 0xFFFFFFFFFFFFFFFF))), _a2))
            }
        }

        return ftr;
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

    function _rect(uint256 label, uint256 tokenId, uint256 x, uint256 y, uint256 r, uint256 g, uint256 b)
    private pure
    returns (string memory output) {
        // Output of the rect element
        output = ''
            '<use href="#r" x="00" y="00" fill="rgb(000,000,000)" onclick="window.open(\'https://c9.ws/      \', \'_blank\')"/>'
            '<text x="00" y="00" class="c9gn" text-anchor="middle">  </text>';

        // Rect position and color
        _coor(output, x, 50);
        _coor(output, y, 57);
        _rgb(output, r, 71);
        _rgb(output, g, 75);
        _rgb(output, b, 79);

        //TokenId window open link to NFT landing page
        bytes6 _tokenId = Helpers.sTokenId(tokenId);
        assembly {
            let dst := add(output, 121)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _tokenId))
        }

        // Text position and label
        _coor(output, x+5, 151);
        _coor(output, y+7, 158);
        _coor(output, label+1, 196);
    }

    function _buildRects(uint256 tokenId, uint256 gameSize)
    private view 
    returns (string memory output) {
        uint256 x;
        uint256 y;
        uint256 z;
        uint256 r;
        uint256 g;
        uint256 b;
        uint256 _tokenId;
        address _tokenOwner;
        uint256[] memory _tokenIds = IC9Game(contractGame).viewGameBoard(tokenId, gameSize);
        for (uint256 i; i<gameSize;) {
            y = 0;
            for(uint256 j; j<gameSize;) {
                if (z != (gameSize*gameSize)/2) {
                    _tokenId = IC9Token(contractToken).tokenByIndex(_tokenIds[z]);
                    _tokenOwner = IC9Token(contractToken).ownerOf(_tokenId);
                    (r, g, b) = _addressToRGB(_tokenOwner);
                    output = string.concat(output, _rect(z, _tokenId, x, y, r, g, b));
                }
                unchecked {
                    y+=10;
                    ++j;
                    ++z;
                }
            }
            unchecked {
                x+=10;    
                ++i;
            }
        }
    }

    function _middleLabel(uint256 gameSize)
    private pure 
    returns (string memory output) {
        // Add the middle number label
        output = '<text x=" 8.5" y=" 9.7" class="c9gn c9gnS" text-anchor="middle">  </text>';
        bytes1 middleCoor = bytes1(Helpers.uintToBytes(gameSize/2));
        uint256 _middleIdx;
        unchecked {
            _middleIdx = (gameSize*gameSize)/2 + 1;
        }
        bytes2 middleLabel = bytes2(Helpers.uintToBytes(_middleIdx));
        assembly {
            let dst := add(output, 41)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), middleCoor))
            dst := add(output, 50)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), middleCoor))
            dst := add(output, 96)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), middleLabel))
        }
    }

    /*
     * @dev Puts together the full SVG image.
     */
    function svgImage(uint256 tokenId, uint256 gameSize)
    external view override
    returns (string memory output) {
        uint256 currentRoundId = IC9Game(contractGame).currentRoundId();
        (,uint256 tokenRoundId,) = IC9Game(contractGame).tokenData(tokenId);
        (address _priorWinner,,) = IC9Game(contractGame).priorWinnerData(tokenId);

        bool expired = tokenRoundId < currentRoundId ? true : false;
        bool priorWinner = _priorWinner == address(0) ? false : true;

        bytes6 _tokenId = Helpers.sTokenId(tokenId);
        bytes6 _currentRoundId = Helpers.sTokenId(currentRoundId);
        bytes6 _tokenRoundId = Helpers.sTokenId(tokenRoundId);

        string memory hdr = _setHDR(
            _tokenId,
            gameSize,
            _tokenRoundId,
            _currentRoundId,
            expired,
            priorWinner
        );
        string memory rects = _buildRects(tokenId, gameSize);
        string memory middle = _middleLabel(gameSize);
        string memory ftr = _setFTR(gameSize, expired, _priorWinner);
        return string.concat(
            hdr,
            rects,
            middle,
            ftr
        );
    }

    function __destroy()
    external {
        selfdestruct(payable(msg.sender));
    }
}