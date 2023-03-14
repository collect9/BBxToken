// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
* @dev Original ERC721 without any extensions.
*/
contract OriginalTokenContract is ERC721 {
    constructor() ERC721("Original NFTs", "ONFTs") {
        for (uint256 i; i<144;) {
            _mint(_msgSender(), i);
            unchecked {++i;}
        }
    }
}
