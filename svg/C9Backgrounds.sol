// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./../abstract/C9Errors.sol";
import "./../utils/Helpers.sol";

contract C9Backgrounds {

    address private _owner;
    uint256 private _bitMaps;
    uint256 private _filterMaps;
    uint256 private _frequencyMaps;
    uint256 private _octaveMaps;

    constructor() {
        _bitMaps = 2236265508087360095996762626638876194385;
        _filterMaps = 57467935144302711919470905843006094509963670152384512;
        _frequencyMaps = 3804199413314552966035659560963;
        _octaveMaps = 8869401141539;
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

    function _matrix(uint256 index)
    private view
    returns(bytes memory matrix) {
        matrix = "0 0 0 0 0 0 0 0 0 0 0 0";
        uint256 _bM = _bitMaps;
        uint256 bitMapOffset;
        unchecked {bitMapOffset = 12*index;}
        for (uint256 i; i<12;) {
            if ((_bM>>bitMapOffset & uint256(1)) == 1) {
                matrix[2*i] = "1";
            }
            unchecked {
                ++i;
                ++bitMapOffset;
            }
        }
    }

    function _filter(uint256 index)
    private view
    returns(bytes memory filter) {
        filter = "0 .0 .0 .0";
        uint256 _fM = _filterMaps;
        uint256 filterMapOffset;
        unchecked {filterMapOffset = 16*index;}
        for (uint256 i; i<4;) {
            filter[3*i] = bytes1(
                Helpers.uintToBytes(
                    _fM>>(filterMapOffset+4*i) & uint256(15)
                )
            );
            unchecked {
                ++i;
            }
        }
    }

    function _octave(uint256 index)
    private view
    returns(bytes32) {
        return Helpers.uintToBytes(
            _octaveMaps>>(4*index) & uint256(15)
        );
    }

    function _frequency(uint256 index)
    private view
    returns(bytes memory frequency) {
        frequency = "0.001";
        uint256 _fInt = _frequencyMaps>>(10*index) & uint256(1023);
        bytes3 _fB = bytes3(
            Helpers.uintToBytes(
                _fInt
            )
        );
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
    }

    function getBackground(uint256 genTag, uint256 specialTier)
    external view
    returns (bytes23 matrix, bytes11 filter, bytes5 freq, bytes1 octave) {
        uint256 colorIndex = specialTier > 0 ? specialTier+5 : genTag;
        matrix = bytes23(_matrix(colorIndex));
        filter = bytes11(_filter(colorIndex));
        freq = bytes5(_frequency(colorIndex));
        octave = bytes1(_octave(colorIndex));
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
    newValueCheck(_bitMaps, value) {
        _bitMaps = value;
    }

    function setOctave(uint256 value)
    external
    onlyOwner()
    newValueCheck(_octaveMaps, value) {
        _octaveMaps = value;
    }
}