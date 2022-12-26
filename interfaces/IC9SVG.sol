// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9SVG {
    function returnSVG(address _address, uint256 _uTokenData, string calldata _sTokenData) external view returns(string memory);
}