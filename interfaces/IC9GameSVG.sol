// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9GameSVG {
    function svgImage(uint256 tokenId, uint256 gameSize)
    external view
    returns (string memory output);
}