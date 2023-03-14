// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* @dev Note: Even though we could have a second event that summarizes 
 * safeTransferBatchFromBatch, it's probably going to be a bit ugly unrolling 
 * something like:
 * event TransferBatchToBatch(address[] from, address indexed to, uint256[][] tokenIds)
 *
 * Additionally safeTransferBatchFromBatch is built to call safeTransferBatchFrom which 
 * emits TransferBatch. For now we're just keeping all of this as simple yet flexible 
 * as possible to demonstrate the purpose of this EIP.
 *
 * Overall: Indexers must update to recognize this extension, so that they look 
 * for the new event to continue to accurately reflect token transfers.
 */
interface IEIP7777 {
    // Only one emit event needed to save gas
    event TransferBatch(address indexed from, address indexed to, uint256[] tokenIds); 

    // Batch transfer from
    function safeTransferBatchFrom(address from, address to, uint256[] calldata tokenIds) external;

    // Batch transfer from to batch
    function safeBatchTransferBatchFrom(address from, address[] calldata to, uint256[][] calldata tokenIds) external;
}