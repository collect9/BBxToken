// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)
pragma solidity >=0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./C9ERC721Base4.sol";

/**
 * @dev A very basic implementation of {ERC721Enumerable} that only includes 
 * _allTokens enumeration. This is useful for non-burnable tokens, or burnable 
 * tokens where ownership gaps in the enumeration are fine. ALl 96-bits of 
 * extra storage in _owners are maintained.
 */
abstract contract ERC721IdEnumBasic is ERC721 {
    // Array of all token ids, used for enumeration
    uint24[] internal _allTokens;

    function _mint(address to, uint256[] calldata tokenIds)
    internal virtual {
        uint256 batchSize = tokenIds.length;
        uint256 tokenData = uint256(uint160(to));
        uint256 _tokenId;
        for (uint256 i; i<batchSize;) {
            _tokenId = tokenIds[i];
            // Add to all tokens list
            _allTokens.push(uint24(_tokenId));
            // Set owner of the token
            _owners[_tokenId] = tokenData;
            emit Transfer(address(0), to, _tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     * @dev Collect9: copied from ERC721Enumerable
     */
    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (index >= _totalSupply) {
            revert TokenEnumIndexOOB(_totalSupply, index);
        }
        return uint256(_allTokens[index]);
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }
}