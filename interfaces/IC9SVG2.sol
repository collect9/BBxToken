// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9SVG {
    function svgImage(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    returns (string memory);
}