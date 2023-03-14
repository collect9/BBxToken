// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./erc721-eip.sol";

/**
* @dev Updated ERC721 with EIP extension.
*/
contract UpdatedTokenContract is ERC721 {
    constructor() ERC721("EIP NFTs", "ENFTs") {
        for (uint256 i; i<144;) {
            _mint(_msgSender(), i);
            unchecked {++i;}
        }
    }
}

