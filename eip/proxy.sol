// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/ieip7777.sol";

/**
* @dev This a proxy contract that one would build to 
* achieve batching of the original ERC721 contract.
* Note: While a proxy contract is no longer needed 
* with the EIP extension, we still include it here for 
* benchmark purposes as other dApps will act as a 
* proxy anyway, thus benchmarks are taken from the proxy.
*/
contract Proxy {

    address public immutable contractTokenOriginal;
    address public immutable contractTokenUpdated;

    constructor(address _contractTokenOriginal, address _contractTokenUpdated) {
        contractTokenOriginal = _contractTokenOriginal;
        contractTokenUpdated = _contractTokenUpdated;
    }

    /**
     * @dev Batched transfer from the original ERC721 contract.
     */
    function safeTransfer(address from, address to, uint256[] calldata tokenIds)
    public {
        uint256 _batchSize = tokenIds.length;
        for (uint256 i; i<_batchSize;) {
            IERC721(contractTokenOriginal).safeTransferFrom(from, to, tokenIds[i]);
            unchecked {++i;}
        }
    }

    /**
     * @dev Batched transfer from the updated ERC721 contract.
     */
    function safeTransferBatch(address from, address to, uint256[] calldata tokenIds)
    public {
        IEIP7777(contractTokenUpdated).safeTransferBatchFrom(from, to, tokenIds);
    }
}