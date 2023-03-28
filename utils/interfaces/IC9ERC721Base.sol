// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IC9ERC721 is IERC721, IERC721Metadata {
    function clearApproved(uint256[] calldata tokenIds) external;
    function getRegistrationFor(address account) external returns (uint256);
    function isRegistered(address account) external returns (bool);
    function safeTransferBatchFrom(address from, address to, uint256[] calldata tokenIds) external;
    function safeBatchTransferBatchFrom(address from, address[] calldata to, uint256[][] calldata tokenIds) external;
    function transferBatchFrom(address from, address to, uint256[] calldata tokenIds) external;

    // Only one emit event needed to save gas
    event TransferBatch(address indexed from, address indexed to, uint256[] tokenIds); 
}