// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./../abstract/C9Errors.sol";
import "./../utils/Helpers.sol";

/*
 * @dev Contract that controls background colors and filter 
 * parameters of the SVG.
 */
contract C9Backgrounds {

    uint256 private _rgbMaps;
    uint256 private _filterMaps;
    uint256 private _frequencyMaps;
    
    address private _owner;
    uint96 private _octaveMaps;

    constructor() {
        _rgbMaps = 13386650909078413403263761003580537709103909416099;
        _filterMaps = 45448518940299844464049894645485953724431708947847424;
        _frequencyMaps = 12677753616095056240239206995971;
        _octaveMaps = uint96(8869401141539);
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) {
            revert Unauthorized();
        }
        _;
    }

    modifier newValueCheck(uint256 oldValue, uint256 newValue) {
        if (newValue == 0) {
            revert ZeroValueError();
        }
        if (newValue == oldValue) {
            revert ValueAlreadySet();
        }
        _;
    }

    /*
     * @dev Filter params. The fifth one is omitted because 
     * it seems to cause undesirable effects outside of 
     * the viewBox when set due to the filter type.
     */
    function _filter(uint256 index)
    private view
    returns(bytes32) {
        bytes memory filter = "2 .0 .0 .6 0'/></filter><filter ";
        uint256 _fM = _filterMaps;
        uint256 filterMapOffset;
        unchecked {filterMapOffset = 16*index;}
        for (uint256 i; i<4;) {
            filter[3*i] = bytes1(
                Helpers.uintToBytes(
                    _fM>>filterMapOffset & uint256(15)
                )
            );
            unchecked {
                ++i;
                filterMapOffset += 4;
            }
        }
        return bytes32(filter);
    }

    function _frequency(uint256 index)
    private view
    returns(bytes32) {
        bytes memory frequency = "0.001' numOctaves='2'/><feCompos";
        uint256 _fInt = _frequencyMaps>>(10*index) & uint256(1023);
        bytes3 _fB = bytes3(
            Helpers.uintToBytes(
                _fInt
            )
        );
        // Depending on length, null bytes may be returned.
        if (_fInt < 10) {
            frequency[4] = _fB[0];
        }
        else if (_fInt < 100) {
            frequency[3] = _fB[0];
            frequency[4] = _fB[1];
        }
        else {
            frequency[2] = _fB[0];
            frequency[3] = _fB[1];
            frequency[4] = _fB[2];
        }
        return bytes32(frequency);
    }

    /*
     * @dev RGB matrix. Each one has 5 values, ie: r1, r2... r5,
     * that may be set.
     */
    function _matrix(uint256 index)
    private view
    returns(bytes32) {
        bytes memory matrix = "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 .0";
        uint256 _rgbM = _rgbMaps;
        uint256 bitMapOffset;
        unchecked {bitMapOffset = 15*index;}
        for (uint256 i; i<15;) {
            if ((_rgbM>>bitMapOffset & uint256(1)) == 1) {
                matrix[2*i] = "1";
            }
            unchecked {
                ++i;
                ++bitMapOffset;
            }
        }
        return bytes32(matrix);
    }

    function _octave(uint256 index)
    private view
    returns(bytes32) {
        return Helpers.uintToBytes(
            _octaveMaps>>(4*index) & uint256(15)
        );
    }

    function getBackground(uint256 genTag, uint256 specialTier)
    external view
    returns (bytes32 matrix, bytes32 filter, bytes32 freq, bytes32 octave) {
        uint256 colorIndex;
        unchecked {colorIndex = specialTier > 0 ? specialTier+5 : genTag;}
        matrix = _matrix(colorIndex);
        filter = _filter(colorIndex);
        freq = _frequency(colorIndex);
        octave = _octave(colorIndex);
    }

    function setFilterMaps(uint256 value)
    external
    onlyOwner()
    newValueCheck(_filterMaps, value) {
        _filterMaps = value;
    }

    function setFrequencies(uint256 value)
    external
    onlyOwner()
    newValueCheck(_frequencyMaps, value) {
        _frequencyMaps = value;
    }

    function setMatrix(uint256 value)
    external
    onlyOwner()
    newValueCheck(_rgbMaps, value) {
        _rgbMaps = value;
    }

    function setOctave(uint256 value)
    external
    onlyOwner()
    newValueCheck(uint256(_octaveMaps), value) {
        _octaveMaps = uint96(value);
    }
}