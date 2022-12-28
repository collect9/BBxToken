// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

uint256 constant GPOS_STEP = 0;
uint256 constant GPOS_CODE = 8;
uint256 constant GPOS_REGISTERED = 24;
uint256 constant REGISTERED = 1;

interface IC9Registrar {
    function cancel() external;
    function getStep(address _address) external view returns(uint256);
    function isRegistered(address _address) external view returns(bool);
    function start() external;
}