// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./../C9OwnerControl.sol";
import "./../abstract/C9Errors.sol";
import "./interfaces/IC9ERC721.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IC9ERC721, C9OwnerControl {
    using Address for address;
    using Strings for uint256;

    uint256 constant EPOS_OWNER = 0;
    uint256 constant EPOS_OWNED_IDX = 160;
    uint256 constant EPOS_ALL_IDX = 184;
    uint256 constant EPOS_TRANSFER_COUNTER = 208;
    uint256 constant EPOS_RESERVED = 232;
    uint256 constant MAX_TRANSFER_BATCH_SIZE = 64;

    bytes32 public constant RESERVED_ROLE = keccak256("RESERVED_ROLE");

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    /* @dev
     * Collect9: optimized to be packed into a single uint256. There is a little 
     * overhead in packing and unpacking, but overall a good chunk of gas is saved 
     * on both minting and transfers as storage space is reduced to 1/3 the original 
     * by packing these./
     */
    mapping(uint256 => uint256) private _owners; // _owner(address), _ownedTokensIndex (u24), _allTokensIndex (u24), _transferCount(u24), _reserved (u24)

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /* @dev Collect9:
     * Copied from ERC721Enumerable
     */
    // Mapping from owner to list of owned token IDs
    /* This could theoretically be lowered to uint16 and store the index within _allTokens
     * but would come at the cost of extra read operations in transfer.
     */
    mapping(address => uint32[]) private _ownedTokens;

    // Array with all token ids, used for enumeration
    uint32[] private _allTokens;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function _setTokenParam(uint256 _packedToken, uint256 _pos, uint256 _val, uint256 _mask)
        internal pure virtual
        returns(uint256) {
            _packedToken &= ~(_mask<<_pos); //zero out only its portion
            _packedToken |= _val<<_pos; //write value back in
            return _packedToken;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
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
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            revert InvalidToken(tokenId);
        }
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     * @dev Collect9: copied from ERC721Enumerable
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        uint256 _length = _ownedTokens[owner].length;
        if (index >= _length) {
            revert OwnerIndexOOB(_length, index);
        }
        return uint256(_ownedTokens[owner][index]);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     * @dev Collect9: copied from ERC721Enumerable
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     * @dev Collect9: copied from ERC721Enumerable
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (index >= _totalSupply) {
            revert TokenEnumIndexOOB(_totalSupply, index);
        }
        return uint256(_allTokens[index]);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenIndex uint256 ID index the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenIndex) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex =  _ownedTokens[from].length - 1;

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = uint32(lastTokenId); // Move the last token to the slot of the to-delete token
            _owners[lastTokenId] = _setTokenParam(
                _owners[lastTokenId],
                EPOS_OWNED_IDX,
                tokenIndex,
                type(uint24).max
            );
        }

        // Deletes the contents at the last position of the array
        _ownedTokens[from].pop();
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenIndex index of token to remove
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenIndex) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = _allTokens.length - 1;

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = uint32(lastTokenId); // Move the last token to the slot of the to-delete token

        // Update the moved token's index
        _owners[lastTokenId] = _setTokenParam(
            _owners[lastTokenId],
            EPOS_ALL_IDX,
            tokenIndex,
            type(uint24).max
        );

        // This also deletes the contents at the last position of the array
        _allTokens.pop();
    }


    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        if (to == owner) {
            revert OwnerAlreadyApproved();
        }
        if (_msgSender() != owner) {
            if (!isApprovedForAll(owner, _msgSender())) {
                revert CallerNotOwnerOrApproved();
            }
        }
        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);
        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Should be possible to clear this without having to transfer.
     */
    function clearApproved(uint256 tokenId) external {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
            revert CallerNotOwnerOrApproved();
        }
        delete _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert NonERC721Receiver();
        }
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return address(uint160(_owners[tokenId]));
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _mint(to, tokenId);
        if (!_checkOnERC721Received(address(0), to, tokenId, data)) {
            revert NonERC721Receiver();
        }
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        if (_exists(tokenId)) {
            revert TokenAlreadyMinted(tokenId);
        }
        // Transfer
        _xfer(address(0), to, tokenId);
        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ownerOf(tokenId);
        uint256 _tokenData = _owners[tokenId];

        // Remove from enumerations
        _removeTokenFromOwnerEnumeration(
            owner,
            uint256(uint24(_tokenData>>EPOS_OWNED_IDX))
        );
        _removeTokenFromAllTokensEnumeration(
            uint256(uint24(_tokenData>>EPOS_ALL_IDX))
        );

        // Clear approvals
        // Tiny gas savings when most users won't have a single token set
        if (_tokenApprovals[tokenId] != address(0)) {
            delete _tokenApprovals[tokenId];
        }

        // Clear tokenID data
        delete _owners[tokenId];
        emit Transfer(owner, address(0), tokenId);
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
    function _xfer(address from, address to, uint256 tokenId)
        private {

        uint256 _tokenData = _owners[tokenId];

        uint256 length;
        // If coming from minter
        if (from == address(0)) {
            length = _allTokens.length;
            _allTokens.push(uint32(tokenId));
            _tokenData = _setTokenParam(
                _tokenData,
                EPOS_ALL_IDX,
                length,
                type(uint24).max
            );
        } else {
            // Else coming from prior owner
            uint256 _tokenIndex = uint256(uint24(_tokenData>>EPOS_OWNED_IDX));
            _removeTokenFromOwnerEnumeration(
                from,
                _tokenIndex
            );

            /*
            Transfer counter can be stored for about ~600 more gas.
             */
            uint256 _xferCounter = uint256(uint24(_tokenData>>EPOS_TRANSFER_COUNTER));
            unchecked {++_xferCounter;}
            _tokenData = _setTokenParam(
                _tokenData,
                EPOS_TRANSFER_COUNTER,
                _xferCounter,
                type(uint24).max
            );
        }

        // Set owned token index
        length = _ownedTokens[to].length; //ERC721.balanceOf(to);
        _ownedTokens[to].push(uint32(tokenId));
        _tokenData = _setTokenParam(
            _tokenData,
            EPOS_OWNED_IDX,
            length,
            type(uint24).max
        );

        // Set new owner
        _tokenData = _setTokenParam(
            _tokenData,
            EPOS_OWNER,
            uint256(uint160(to)),
            type(uint160).max
        );

        // Write back to storage
        _owners[tokenId] = _tokenData;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        address _owner = ownerOf(tokenId);
        if (_owner != from) {
            revert TransferFromIncorrectOwner(_owner, from);
        }
        if (_msgSender() != _owner) {
            if (!isApprovedForAll(_owner, _msgSender())) {
                revert CallerNotOwnerOrApproved();
            }
        }
        if (to == address(0)) {
            revert ZeroAddressInvalid();
        }
        if (to == from) {
            revert TransferFromToSame();
        }
        
        _beforeTokenTransfer(from, to, tokenId, 1);

        // Clear approvals from the previous owner
        // Saves about ~100 gas when not set (most cases)
        if (_tokenApprovals[tokenId] != address(0)) {
            delete _tokenApprovals[tokenId];
        }

        // Transfer
        _xfer(from, to, tokenId);
        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        if (operator == owner) {
            revert ApproveToCaller();
        }
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        if (!_exists(tokenId)) {
            revert InvalidToken(tokenId);
        }
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert NonERC721Receiver();
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens will be transferred to `to`.
     * - When `from` is zero, the tokens will be minted for `to`.
     * - When `to` is zero, ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual {}

    /**
     * @dev Hook that is called after any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens were transferred to `to`.
     * - When `from` is zero, the tokens were minted for `to`.
     * - When `to` is zero, ``from``'s tokens were burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual {}

    /**
     * @dev Collect9 - custom batch functions
     */
    function _transferBatch(address from, address to, uint256[] calldata _tokenId)
        private {
            uint256 _batchSize = _tokenId.length;
            if (_batchSize > MAX_TRANSFER_BATCH_SIZE) {
                revert BatchSizeTooLarge(MAX_TRANSFER_BATCH_SIZE, _batchSize);
            }
            for (uint256 i; i<_batchSize;) {
                transferFrom(from, to, _tokenId[i]);
                unchecked {++i;}
            }
    }

    /**
     * @dev Allows safe batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Max batch size is 64.
     */
    function safeTransferFrom(address from, address to, uint256[] calldata tokenId)
        external {
            _transferBatch(from, to, tokenId);
            // Only need to check one time
            if (!_checkOnERC721Received(from, to, tokenId[0], "")) {
                revert NonERC721Receiver();
            }
    }

    /**
     * @dev Allows batch transfer to many addresses at once. This will save
     * around ~20-25% gas with 4 or more addresses sent to at once. This only has a 
     * safe transfer version to prevent accidents of sending to a 
     * non-ERC721 receiver.
     */
    function safeTransferFrom(address from, address[] calldata to, uint256[] calldata tokenId)
        external {
            uint256 _batchSize = tokenId.length;
            if (_batchSize > MAX_TRANSFER_BATCH_SIZE) {
                revert BatchSizeTooLarge(MAX_TRANSFER_BATCH_SIZE, _batchSize);
            }
            uint256 _addressBookSize = to.length;
            if (_addressBookSize != _batchSize) {
                revert TransferSizeMismatch(_addressBookSize, _batchSize);
            }
            for (uint256 i; i<_batchSize;) {
                _safeTransfer(from, to[i], tokenId[i], "");
                unchecked {++i;}
            }
    }

    /**
     * @dev Allows batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Max batch size is 64.
     */
    function transferFrom(address from, address to, uint256[] calldata tokenId)
        external {
            _transferBatch(from, to, tokenId);
    }

    /**
     * @dev Get all params stored for tokenId.
     */
    function getTokenParamsERC(uint256 _tokenId)
        external view
        returns(uint256[4] memory params) {
            uint256 _packedToken = _owners[_tokenId];
            params[0] = uint256(uint24(_packedToken>>EPOS_OWNED_IDX));
            params[1] = uint256(uint24(_packedToken>>EPOS_ALL_IDX));
            params[2] = uint256(uint24(_packedToken>>EPOS_TRANSFER_COUNTER));
            params[3] = uint256(uint24(_packedToken>>EPOS_RESERVED));
    }

    function _setReservedERC(uint256 _tokenId, uint256 _data)
        private {
            _requireMinted(_tokenId);
            _owners[_tokenId] = _setTokenParam(
                _owners[_tokenId],
                EPOS_RESERVED,
                _data,
                type(uint24).max
            );
    }

    /**
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function setReservedERC(uint256[2][] calldata _data)
        external override
        onlyRole(RESERVED_ROLE) {
            uint256 _batchSize = _data.length;
            for (uint256 i; i<_batchSize;) {
                _setReservedERC(_data[i][0], _data[i][1]);
                unchecked {++i;}
            }
    }
}