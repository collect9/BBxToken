// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "./interfaces/IC9ERC721Base.sol";
import "./interfaces/IERC4906.sol";

import "./../C9OwnerControl.sol";
import "./../abstract/C9Errors.sol";

uint256 constant MAX_TRANSFER_BATCH_SIZE = 128;

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IC9ERC721Base, IERC2981, IERC4906, C9OwnerControl {
    using Address for address;
    using Strings for uint256;

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Total supply
    uint256 internal _totalSupply;

    // Token counter
    uint256 internal _tokenCounter;
    
    // Mapping from token ID to owner address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Royalties info
    address _royaltyReceiver;
    uint96 private _royalty;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint96 royalty_) {
        name = name_;
        symbol = symbol_;
        _royalty = royalty_;
        _royaltyReceiver = owner;
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    modifier requireMinted(uint256 tokenId) {
        if (!_exists(tokenId)) {
            revert InvalidToken(tokenId);
        }
        _;
    }

    modifier validTo(address to) {
        if (to == address(0)) {
            revert ZeroAddressInvalid();
        }
        _;
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
        address tokenOwner = ownerOf(tokenId);
        if (tokenOwner != from) {
            revert TransferFromIncorrectOwner(tokenOwner, from);
        }
        /*
        Clear approvals from the previous owner.
        We restrict reading and writing to the first 160 bits only in case the remaining 
        96 bits are used for storage.
        */
        if (uint256(uint160(_tokenApprovals[tokenId])) != 0) {
            _tokenApprovals[tokenId] = _setTokenParam(
                _tokenApprovals[tokenId], 0, 0, type(uint160).max
            );
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
        emit Transfer(_ownerOf(tokenId), address(0), tokenId);
        delete _tokenApprovals[tokenId];
        delete _owners[tokenId];
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
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || isApprovedForAll(tokenOwner, spender) || getApproved(tokenId) == spender);
    }

    function _mint(address to, uint256 batchSize)
    internal virtual {
        uint256 _to = uint256(uint160(to));
        uint256 _tokenId = _tokenCounter;
        uint256 _tokenIdMax = _tokenId+batchSize;
        for (_tokenId; _tokenId<_tokenIdMax;) {
            _owners[_tokenId] = _to;
            emit Transfer(address(0), to, _tokenId);
            unchecked {
                ++_tokenId;
            }
        }
        unchecked {
            _balances[to] += batchSize; 
            _totalSupply += batchSize;  
        }
        _tokenCounter = _tokenId;
    }

    function _mint(address[] calldata to, uint256 batchSize)
    internal virtual {
        uint256 _tokenId = _tokenCounter;
        for (uint256 i; i<batchSize;) {
            _owners[_tokenId] = uint256(uint160(to[i]));
            ++_balances[to[i]]; 
            emit Transfer(address(0), to[i], _tokenId);
            unchecked {
                ++_tokenId;
                ++i;
            }
        }
        unchecked {
            _totalSupply += batchSize;  
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
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 batchsize)
    internal virtual {
        _safeMint(to, batchsize, "");
    }
    
    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 batchsize, bytes memory data)
    internal virtual {
        _mint(to, batchsize);
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
    function _setApprovalForAll(address tokenOwner, address operator, bool approved)
    internal virtual {
        if (operator == tokenOwner) {
            revert ApproveToCaller();
        }
        _operatorApprovals[tokenOwner][operator] = approved;
        emit ApprovalForAll(tokenOwner, operator, approved);
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
     *  As opposed to {transferFrom}, this imposes no restrictions on _msgSender().
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId)
    internal virtual
    validTo(to) {
        // Before transfer checks
        _beforeTokenTransfer(from, to, tokenId, 1);
        // Set new owner
        _owners[tokenId] = _setTokenParam(
            _owners[tokenId],
            0,
            uint256(uint160(to)),
            type(uint160).max
        );
        // Emit event
        emit Transfer(from, to, tokenId);
        // Update balances
        unchecked {
            --_balances[from];
            ++_balances[to];
        }
    }

    /**
     * @dev We have a separate function here because we don't want to read/write 
     * to balances for every token. One time update at the end only.
     */
    function _transfer(address from, address to, uint256[] calldata tokenIds)
    internal virtual
    validTo(to) {
        uint256 tokenId;
        uint256 _to = uint256(uint160(to)); // Convert one time
        uint256 batchSize = tokenIds.length;
        for (uint256 i; i<batchSize;) {
            tokenId = tokenIds[i];
            // Before transfer checks
            _beforeTokenTransfer(from, to, tokenId, 1);
            // Set new owner
            _owners[tokenId] = _setTokenParam(
                _owners[tokenId],
                0,
                _to,
                type(uint160).max
            );
            // Emit event
            emit Transfer(from, to, tokenId);
            unchecked {++i;}
        }
        // Update balances one time
        unchecked {
            _balances[from] -= batchSize;
            _balances[to] += batchSize;
        }
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId)
    public virtual
    override {
        address tokenOwner = ownerOf(tokenId);
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
            tokenOwner = ownerOf(tokenId);
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
        address tokenOwner = ownerOf(tokenId);
        unchecked {
            --_balances[tokenOwner];
            --_totalSupply;
        }
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
            revert CallerNotOwnerOrApproved();
        }
        _burn(tokenId);
    }

    /**
     * @dev Batch burn function for convenience and
     * gas savings per burn.
     */
    function burn(uint256[] calldata tokenIds)
    external virtual {
        uint256 _batchSize = tokenIds.length;
        address tokenOwner = ownerOf(tokenIds[0]);
        unchecked {
            _balances[tokenOwner] -= _batchSize;
            _totalSupply -= _batchSize;
        }
        for (uint256 i; i<_batchSize;) {
            if (!_isApprovedOrOwner(_msgSender(), tokenIds[i])) {
                revert CallerNotOwnerOrApproved();
            }
            _burn(tokenIds[i]);
            unchecked {++i;}
        }
    }

    /**
     * @dev It's not obvious how to clear this in the original contract.
     * User can just set address zero, or call this method.
     * Should be possible to clear (in an obvious way) this without having to transfer.
     */
    function clearApproved(uint256 tokenId) external {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) {
            revert CallerNotOwnerOrApproved();
        }
        delete _tokenApprovals[tokenId];
    }

    /**
     * @dev Batch version of clear approved.
     */
    function clearApproved(uint256[] calldata tokenIds) external {
        uint256 _batchSize = tokenIds.length;
        for (uint256 i; i<_batchSize;) {
            if (!_isApprovedOrOwner(_msgSender(), tokenIds[i])) {
                revert CallerNotOwnerOrApproved();
            }
            delete _tokenApprovals[tokenIds[i]];
        }
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId)
    public view virtual
    override
    requireMinted(tokenId)
    returns (address) {
        return address(uint160(_tokenApprovals[tokenId]));
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address tokenOwner, address operator)
    public view virtual
    override
    returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
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
     * @dev See {IERC2981-royaltyInfo}.
     */
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external view virtual override
        returns (address receiver, uint256 royaltyAmount) {
            receiver = owner;
            royaltyAmount = (salePrice * _royalty) / 10000;
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
     * @dev Allows contract to have a separate royalties receiver 
     * address from owner. The default receiver is owner.
     */
    function setRoyaltyReceiver(address _address)
        external virtual
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_address == address(0)) {
                revert ZeroAddressInvalid();
            }
            _royaltyReceiver = _address;
    }

    /**
     * @dev Sets the default royalties amount.
     */
    function setRoyalty(uint96 _fraction)
        external virtual
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_royalty == _fraction) {
                revert ValueAlreadySet();
            }
            _royalty = _fraction;
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
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IERC4906).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
    public view virtual
    override
    requireMinted(tokenId)
    returns (string memory) {
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function totalSupply()
    public view virtual 
    returns (uint256) {
        return _totalSupply;
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