// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)
pragma solidity >=0.8.17;
import "./../abstract/C9Struct4.sol";

abstract contract C9Context is C9Struct {

    /*
     * @dev Since validity is looked up in many places, we have a 
     * private function for it.
     */
    function _currentVId(uint256 tokenData)
    internal pure
    returns (uint256) {
        return _viewPackedData(tokenData, MPOS_VALIDITY, MSZ_VALIDITY);
    }

    function _setTokenParam(uint256 packedData, uint256 pos, uint256 val, uint256 mask)
    internal pure virtual
    returns(uint256) {
        packedData &= ~(mask<<pos); //zero out only its portion
        packedData |= val<<pos; //write value back in
        return packedData;
    }

    function _setDataValidity(uint256 packedData, uint256 validity)
    internal pure virtual
    returns (uint256) {
        return _setTokenParam(
            packedData,
            MPOS_VALIDITY,
            validity,
            MASK_VALIDITY
        );
    }

    function _viewPackedData(uint256 packedData, uint256 offset, uint256 size)
    public pure virtual
    returns (uint256 output) {
        uint256 _mask;
        unchecked {
            _mask = (2**(256-size))-1;
            _mask = ~(_mask<<size);
        }
        packedData = packedData>>offset & _mask;
        output = packedData < _mask ? packedData : _mask;
    }

}