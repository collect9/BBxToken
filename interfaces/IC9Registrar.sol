// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9Registrar {
    function add(bytes32 _ksig32, bool _replace) external;
    function getDataFor(address _address) external view returns (bytes32 data);
    function remove() external;
    function isRegistered(address _address) external view returns (bool registered);
}