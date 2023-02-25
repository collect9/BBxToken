// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9GameMetaData {
    function metaNameDesc(uint256 tokenId)
    external pure
    returns(bytes memory);

    function metaAttributes(uint256 tokenId, uint256 threshold)
    external view
    returns (bytes memory b);
}