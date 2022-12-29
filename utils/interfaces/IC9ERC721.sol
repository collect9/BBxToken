// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IC9ERC721 is IERC721, IERC721Enumerable, IERC721Metadata {
    function clearApproved(uint256 tokenId) external;
    function getTokenParamsERC(uint256 _tokenId) external view returns(uint256[5] memory params);
    function safeTransferFrom(address from, address to, uint256[] calldata _tokenId) external;
    function safeTransferFrom(address from, address[] calldata to, uint256[] calldata _tokenId) external;
    function transferFrom(address from, address to, uint256[] calldata _tokenId) external;
}