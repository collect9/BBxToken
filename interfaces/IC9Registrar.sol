// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

uint256 constant GPOS_STEP = 0;
uint256 constant GPOS_CODE = 8;
uint256 constant GPOS_REGISTERED = 24;
uint256 constant REGISTERED = 1;

error AddressAlreadyRegistered(); //0x2d42c772
error AddressNotInProcess(); //0x286d0071
error CodeMismatch(); //0x179708c0
error WrongProcessStep(uint256 expected, uint256 received); //0x58f6fd94

interface IC9Registrar {
    function cancel() external;
    function getStep(address _address) external view returns(uint256);
    function isRegistered(address _address) external view returns(bool);
    function start() external;
}