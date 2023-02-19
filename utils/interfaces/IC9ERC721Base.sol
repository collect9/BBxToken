// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IC9ERC721Base is IERC721, IERC721Metadata {
    function clearApproved(uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256[] calldata tokenId) external;
    function safeTransferFrom(address from, address[] calldata to, uint256[] calldata tokenId) external;
    function transferFrom(address from, address to, uint256[] calldata tokenId) external;
}