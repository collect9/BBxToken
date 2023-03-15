// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* @dev Note: Interface for EIP-6670
 */
interface IERC6670 {
    // Only one emit event needed to save gas
    event TransferBatch(address indexed from, address indexed to, uint256[] tokenIds); 

    // Batch transfer from
    function safeTransferBatchFrom(address from, address to, uint256[] calldata tokenIds) external;

    // Batch transfer from to batch
    function safeBatchTransferBatchFrom(address from, address[] calldata to, uint256[][] calldata tokenIds) external;
}