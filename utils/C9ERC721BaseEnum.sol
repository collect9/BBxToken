// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)
pragma solidity >=0.8.17;

import "./C9ERC721Base.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
abstract contract ERC721OwnerEnumerable is ERC721 {
    mapping(address => uint24[]) internal _ownedTokens;

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _removeTokenFromOwnerEnumeration(ownerOf(tokenId), tokenId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        if (owner == address(0)) {
            revert ZeroAddressInvalid();
        }
        return _ownedTokens[owner].length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     * @dev Collect9: copied from ERC721Enumerable
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        uint256 _length = _ownedTokens[owner].length;
        if (index >= _length) {
            revert OwnerIndexOOB(_length, index);
        }
        return uint256(_ownedTokens[owner][index]);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = _ownedTokens[from].length - 1;

        // When the token to delete is the last token, the swap operation is unnecessary
        uint256 tokenIndex = uint256(uint16(_owners[tokenId]>>160));
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = uint24(lastTokenId); // Move the last token to the slot of the to-delete token
            _owners[lastTokenId] = _setTokenParam(
                _owners[lastTokenId],
                160,
                tokenIndex,
                type(uint16).max
            );
        }

        // Deletes the contents at the last position of the array
        _ownedTokens[from].pop();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        // Remove from old owner enumerations
        _removeTokenFromOwnerEnumeration(owner, tokenId);
        // Add to new owner enumerations
        _ownedTokens[to].push(uint24(tokenId));
    }

    function _mint(address to, uint256 batchSize)
    internal virtual override {
        uint256 _to = uint256(uint160(to));
        uint256 _tokenId = _tokenCounter;
        uint256 _tokenIdN = _tokenId+batchSize;
        for (_tokenId; _tokenId<_tokenIdN;) {
            _owners[_tokenId] = _to;
            _ownedTokens[to].push(uint24(_tokenId));
            emit Transfer(address(0), to, _tokenId);
            unchecked {
                ++_tokenId;
            }
        }
        unchecked {
            _totalSupply += batchSize;  
        }
        _tokenCounter = _tokenId;
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId)
    internal virtual override {
        if (to == address(0)) {
            revert ZeroAddressInvalid();
        }
        _beforeTokenTransfer(from, to, tokenId, 1);
        // Set new owner
        _owners[tokenId] = _setTokenParam(
            _owners[tokenId], 0, uint160(to), type(uint160).max
        );
        emit Transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint256[] calldata tokenIds)
    internal virtual override {
        if (to == address(0)) {
            revert ZeroAddressInvalid();
        }
        uint256 _batchSize = tokenIds.length;
        uint256 tokenId;
        uint160 _to = uint160(to);
        for (uint256 i; i<_batchSize;) {
            tokenId = tokenIds[i];
            _beforeTokenTransfer(from, to, tokenId, 1);
            // Set new owner
            _owners[tokenId] = _setTokenParam(
                _owners[tokenId], 0, _to, type(uint160).max
            );
            unchecked {++i;}
            emit Transfer(from, to, tokenId);
        }
    }
}