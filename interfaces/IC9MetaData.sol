// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9MetaData {
    function b64Image(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    returns (bytes memory);

    function metaData(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    returns (bytes memory);

    function svgImage(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    returns (bytes memory);
}