// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IC9ERC721Base.sol";

import "./../C9OwnerControl.sol";
import "./../abstract/C9Errors.sol";

uint256 constant MAX_TRANSFER_BATCH_SIZE = 128;

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract C9ERC721 is Context, ERC165, IC9ERC721Base, C9OwnerControl {
    using Address for address;
    using Strings for uint256;

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Total supply
    uint256 public totalSupply;

    // Token counter
    uint256 internal _tokenCounter;
    
    // Mapping from token ID to owner address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) internal _balances;

    // Mapping from token ID to approved address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

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
    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
    internal virtual {}

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId)
    internal virtual {
        _tokenApprovals[tokenId] = _setTokenParam(
            _tokenApprovals[tokenId],
            0,
            uint160(to),
            type(uint160).max
        );
        emit Approval(_ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI()
    internal view virtual
    returns (string memory) {
        return "";
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
    function _beforeTokenTransfer(address from, address /*to*/, uint256 tokenId, uint256 /*batchSize*/)
    internal virtual {
        // Make sure owner is from
        address _owner = _ownerOf(tokenId);
        if (_owner != from) {
            revert TransferFromIncorrectOwner(_owner, from);
        }
        // Clear approvals from the previous owner
        uint256 __tokenApprovals = _tokenApprovals[tokenId];
        if (uint160(__tokenApprovals) != 0) {
            __tokenApprovals = _setTokenParam(
                __tokenApprovals, 0, 0, type(uint160).max
            );
            _tokenApprovals[tokenId] = __tokenApprovals;
        }
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
    function _burn(uint256 tokenId)
    internal virtual {
        delete _tokenApprovals[tokenId];
        delete _owners[tokenId];
        emit Transfer(_ownerOf(tokenId), address(0), tokenId);
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
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
    private
    returns (bool) {
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
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId)
    internal view virtual
    returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
    internal view virtual
    returns (bool) {
        address tokenOwner = _ownerOf(tokenId);
        return (spender == tokenOwner || isApprovedForAll(tokenOwner, spender) || getApproved(tokenId) == spender);
    }

    function _mint(address to, uint256 N)
    internal virtual {
        uint160 _to = uint160(to);
        uint256 _tokenId = _tokenCounter;
        uint256 _tokenIdN = _tokenId+N;
        address _zero = address(0);
        for (_tokenId; _tokenId<_tokenIdN;) {
            _owners[_tokenId] = _to;
            emit Transfer(_zero, to, _tokenId);
            unchecked {
                ++_tokenId;
            }
        }
        unchecked {
            _balances[to] += N; 
            totalSupply += N;  
        }
        _tokenCounter = _tokenId;
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     */
    function _ownerOf(uint256 tokenId)
    internal view virtual
    returns (address) {
        return address(uint160(_owners[tokenId]));
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId)
    internal view virtual {
        if (!_exists(tokenId)) {
            revert InvalidToken(tokenId);
        }
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
    function _safeMint(address to, uint256 N)
    internal virtual {
        _safeMint(to, N, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 N, bytes memory data)
    internal virtual {
        _mint(to, N);
        uint256 _lastTokenId = _tokenCounter-1;
        if (!_checkOnERC721Received(address(0), to, _lastTokenId, data)) {
            revert NonERC721Receiver();
        }
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
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data)
    internal virtual {
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert NonERC721Receiver();
        }
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address owner, address operator, bool approved)
    internal virtual {
        if (operator == owner) {
            revert ApproveToCaller();
        }
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _setTokenParam(uint256 packedToken, uint256 pos, uint256 val, uint256 mask)
    internal pure virtual
    returns(uint256) {
        packedToken &= ~(mask<<pos); //zero out only its portion
        packedToken |= val<<pos; //write value back in
        return packedToken;
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
    internal virtual {
        if (to == address(0)) {
            revert ZeroAddressInvalid();
        }
        _beforeTokenTransfer(from, to, tokenId, 1);
        
        // Set new owner
        _owners[tokenId] = _setTokenParam(
            _owners[tokenId], 0, uint160(to), type(uint160).max
        );
        // Update balances
        unchecked {
            --_balances[from];
            ++_balances[to];
        }
        emit Transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint256[] calldata tokenIds)
    internal virtual {
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
        unchecked {
            _balances[from] -= _batchSize;
            _balances[to] += _batchSize;
        }
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId)
    public virtual
    override {
        address tokenOwner = _ownerOf(tokenId);
        if (to == tokenOwner) {
            revert OwnerAlreadyApproved();
        }
        if (_msgSender() != tokenOwner) {
            if (!isApprovedForAll(tokenOwner, _msgSender())) {
                revert CallerNotOwnerOrApproved();
            }
        }
        _approve(to, tokenId);
    }

    function approve(address[] calldata to, uint256[] calldata tokenIds)
    external virtual {
        uint256 _batchSize = tokenIds.length;
        if (_batchSize > MAX_TRANSFER_BATCH_SIZE) {
            revert BatchSizeTooLarge(MAX_TRANSFER_BATCH_SIZE, _batchSize);
        }
        uint256 _addressBookSize = to.length;
        if (_addressBookSize != _batchSize) {
            revert TransferSizeMismatch(_addressBookSize, _batchSize);
        }
        address tokenOwner;
        uint256 tokenId;
        for (uint256 i; i<_batchSize;) {
            tokenId = tokenIds[i];
            tokenOwner = _ownerOf(tokenId);
            if (to[i] == tokenOwner) {
                revert OwnerAlreadyApproved();
            }
            if (_msgSender() != tokenOwner) {
                if (!isApprovedForAll(tokenOwner, _msgSender())) {
                    revert CallerNotOwnerOrApproved();
                }
            }
            _approve(to[i], tokenId);
            unchecked {++i;}
        }
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address tokenOwner)
    public view virtual
    override
    returns (uint256) {
        if (tokenOwner == address(0)) {
            revert ZeroAddressInvalid();
        }
        return _balances[tokenOwner];
    }

    /**
     * @dev Token burn.
     */
    function burn(uint256 tokenId)
    public virtual {
        address _owner = _ownerOf(tokenId);
        unchecked {
            --_balances[_owner];
            --totalSupply;
        }
        if (msg.sender != _owner) {
            revert CallerNotOwnerOrApproved();
        }
        _burn(tokenId);
    }

    /**
     * @dev Batch burn function for convenience.
     */
    function burn(uint256[] calldata tokenIds)
    external virtual {
        uint256 _batchSize = tokenIds.length;
        address _owner = _ownerOf(tokenIds[0]);
        unchecked {
            _balances[_owner] -= _batchSize;
            totalSupply -= _batchSize;
        }
        for (uint256 i; i<_batchSize;) {
            if (msg.sender != _ownerOf(tokenIds[i])) {
                revert CallerNotOwnerOrApproved();
            }
            _burn(tokenIds[i]);
            unchecked {++i;}
        }
    }

    /**
     * @dev Should be possible to clear (in an obvious way) this without having to transfer.
     */
    function clearApproved(uint256 tokenId) external {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
            revert CallerNotOwnerOrApproved();
        }
        delete _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId)
    public view virtual
    override
    returns (address) {
        _requireMinted(tokenId);
        return address(uint160(_tokenApprovals[tokenId]));
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
    public view virtual
    override
    returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId)
    public view virtual
    override
    returns (address) {
        address tokenOwner = _ownerOf(tokenId);
        if (tokenOwner == address(0)) {
            revert InvalidToken(tokenId);
        }
        return tokenOwner;
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId)
    public virtual
    override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
    public virtual
    override {
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Allows safe batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Max batch size is 64.
     */
    function safeTransferFrom(address from, address to, uint256[] calldata tokenIds)
    external {
        _transfer(from, to, tokenIds);
        // Only need to check one time
        if (!_checkOnERC721Received(from, to, tokenIds[0], "")) {
            revert NonERC721Receiver();
        }
    }

    /**
     * @dev Allows batch transfer to many addresses at once. This will save
     * around ~20-25% gas with 4 or more addresses sent to at once. This only has a 
     * safe transfer version to prevent accidents of sending to a 
     * non-ERC721 receiver.
     */
    function safeTransferFrom(address from, address[] calldata to, uint256[] calldata tokenIds)
    external {
        uint256 _batchSize = tokenIds.length;
        if (_batchSize > MAX_TRANSFER_BATCH_SIZE) {
            revert BatchSizeTooLarge(MAX_TRANSFER_BATCH_SIZE, _batchSize);
        }
        uint256 _addressBookSize = to.length;
        if (_addressBookSize != _batchSize) {
            revert TransferSizeMismatch(_addressBookSize, _batchSize);
        }
        for (uint256 i; i<_batchSize;) {
            _safeTransfer(from, to[i], tokenIds[i], "");
            unchecked {++i;}
        }
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved)
    public virtual
    override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
    public view virtual
    override(AccessControl, ERC165, IERC165)
    returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
    public view virtual
    override
    returns (string memory) {
        _requireMinted(tokenId);
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId)
    public virtual
    override {
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Allows batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Max batch size is 64.
     */
    function transferFrom(address from, address to, uint256[] calldata tokenIds)
    external virtual {
        _transfer(from, to, tokenIds);
    }
}