// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IC9ERC721 is IERC721, IERC721Enumerable, IERC721Metadata {
    function safeTransferFromBatch(address from, address to, uint256[] calldata _tokenId) external;
    function safeTransferFromMulti(address from, address[] calldata to, uint256[] calldata _tokenId) external;
    function transferFromBatch(address from, address to, uint256[] calldata _tokenId) external;
}