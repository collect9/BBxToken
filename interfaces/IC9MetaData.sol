// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9MetaData {
    function metaNameDesc(uint256 _tokenId, uint256 _uTokenData, string calldata _name) external view returns(bytes memory);
    function metaAttributes(uint256 _uTokenData) external view returns (bytes memory b);
}