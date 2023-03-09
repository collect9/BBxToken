// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./interfaces/IERC4906.sol";
import "./interfaces/IC9ERC721Base.sol";


import "./C9Context.sol";
import "./../C9OwnerControl.sol";
import "./../abstract/C9Errors.sol";
import "./../abstract/C9Struct3.sol";

uint256 constant MAX_TRANSFER_BATCH_SIZE = 128;

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 *
 * Collect9 updates the base ERC721 to include the following:
 * 1. tokenId mapping from (uint256 => address) to (uint256 => uint256)
 *    The address mapping costs the same as the uint256 mapping. Thus the uint256 mapping 
 *    gains 96-bits of extra storage space for token meta data purposes.
 * 2. Batching capabilities in minting and transferring. This removes the significant 
 *    per-call overhead when minting or transfering more than one token at a time.
 * 3. IERC4906 event call in beforeTokenTransfer() to update the token's meta data 
 *    at marketplaces every time the token is transferred. This is useful for dynamic 
 *    content tokens. Otherwise it can be commented out.
 * 4. ERC2981 included in the form of global royalties. This is a very light-weight
 *    implementation and does not include customizable per-token royalty info. All token 
 *    royalties are the same, and the receiver is the contract deployer.
 * 5. Enhanced ownership control via C9OwnerControl.
 */
contract ERC721 is C9Context, ERC165, IC9ERC721Base, IERC2981, IERC4906, C9OwnerControl, C9Struct {
    using Address for address;
    using Strings for uint256;

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Total supply
    uint256 internal _totalSupply;
    
    // Mapping from token ID to owner address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _owners;

    // Mapping owner address to token count
    /* Updated to be packed freeing storage for any address mapping information. Balance
       doesn't need to be any larger than the maxTokenId type can possibly reach. */
    mapping(address => uint256) internal _balances;

    // Mapping from token ID to approved address
    /* Updated to be packed, uint160 (default address) with 96 extra bits of custom storage.
       Note that tokenApprovals are not often used by users, so this storage space should 
       only be used as a last resort.
       Note that even not using the extra storage, this has been tested to not add any 
       transfer gas costs, and in fact even reduced it slightly.*/
    mapping(uint256 => uint256) internal _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /* Basic royalties info. Note that EIP-2981 assigns per token which is a waste 
       if all tokens will have the same royalty.*/
    address internal _royaltyReceiver;
    uint96 internal _royalty;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint256 royalty_) {
        name = name_;
        symbol = symbol_;
        _royalty = uint96(royalty_);
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
     *
     * This has been updated to add an on-chain transfer counter which adds around ~700 gas per transfer.
     */
    function _afterTokenTransfer(address from, address to, uint256 /*firstTokenId*/, uint256 batchSize)
    internal virtual {
        // Copy from storage first
        uint256 balancesFrom = _balances[from];
        uint256 balancesTo = _balances[to];

        // Parameters to update, token owners balances and transfer counts
        uint256 balanceFrom = uint256(uint64(balancesFrom));
        uint256 xfersFrom = balancesFrom>>192;
        uint256 balanceTo = uint256(uint64(balancesTo));
        uint256 xfersTo = balancesTo>>192;

        // Update balances and transfer counter
        unchecked {
            balanceFrom -= batchSize;
            xfersFrom += batchSize;
            balanceTo += batchSize;
            xfersTo += batchSize;
        }

        // Set packed values in memory
        balancesFrom = _setTokenParam(
            balancesFrom,
            0,
            balanceFrom,
            type(uint64).max
        );
        balancesFrom = _setTokenParam(
            balancesFrom,
            192,
            xfersFrom,
            type(uint64).max
        );

        balancesTo = _setTokenParam(
            balancesTo,
            0,
            balanceTo,
            type(uint64).max
        );
        balancesTo = _setTokenParam(
            balancesTo,
            192,
            xfersTo,
            type(uint64).max
        );

        // Copy back to storage
        _balances[from] = balancesFrom;
        _balances[to] = balancesTo;
    }

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
            uint256(uint160(to)),
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
    function _beforeTokenTransfer(address from, address /*to*/, uint256 firstTokenId, uint256 /*batchSize*/)
    internal virtual {
        // Make sure from is correct
        address tokenOwner = ownerOf(firstTokenId);
        if (tokenOwner != from) {
            revert TransferFromIncorrectOwner(tokenOwner, from);
        }
        // Make sure the caller is owner
        if (_msgSender() != tokenOwner) {
            if (!isApprovedForAll(tokenOwner, _msgSender())) {
                revert CallerNotOwnerOrApproved(firstTokenId, tokenOwner, _msgSender());
            }
        }
        /*
        Clear approvals from the previous owner.
        We restrict reading and writing to the first 160 bits only in case the remaining 
        96 bits are used for storage.
        The if statement saves ~200 gas when no approval is set (most users).
        */
        if (uint256(uint160(_tokenApprovals[firstTokenId])) != 0) {
            _tokenApprovals[firstTokenId] = _setTokenParam(
                _tokenApprovals[firstTokenId], 0, 0, type(uint160).max
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
        return _owners[tokenId] != 0;
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

    function _mint(address to, uint256 firstTokenId, uint256 batchSize)
    internal virtual {
        uint256 _to = uint256(uint160(to));
        uint256 _tokenIdLast = firstTokenId+batchSize;
        uint256 _tokenId = firstTokenId;
        for (_tokenId; _tokenId<_tokenIdLast;) {
            _owners[_tokenId] = _to;
            emit Transfer(address(0), to, _tokenId);
            unchecked {
                ++_tokenId;
            }
        }
        // Update supply and balances one time
        unchecked {
            _balances[to] += batchSize; 
            _totalSupply += batchSize;  
        }
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
    function _safeMint(address to, uint256 firstTokenId, uint256 batchSize)
    internal virtual {
        _safeMint(to, firstTokenId, batchSize, "");
    }
    
    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 firstTokenId, uint256 batchSize, bytes memory data)
    internal virtual {
        _mint(to, firstTokenId, batchSize);
        // Only check the first token
        if (!_checkOnERC721Received(address(0), to, firstTokenId, data)) {
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

    function _safeTransfer(address from, address to, uint256[] calldata tokenIds, bytes memory data)
    internal virtual {
        _transfer(from, to, tokenIds);
        // Only check the first token
        if (!_checkOnERC721Received(from, to, tokenIds[0], data)) {
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

    function __transfer(uint256 to, uint256 tokenId)
    internal virtual {
        uint256 tokenData = _owners[tokenId];
        uint256 tokenTransferCount = uint256(uint24(tokenData>>MPOS_XFER_COUNTER));
        unchecked {++tokenTransferCount;}

        // Set new owner
        tokenData = _setTokenParam(
            tokenData,
            0,
            to,
            type(uint160).max
        );
        // Update transfer count
        tokenData = _setTokenParam(
            tokenData,
            MPOS_XFER_COUNTER,
            tokenTransferCount,
            type(uint24).max
        );

        // Copy back to storage
        _owners[tokenId] = tokenData;
    }

    function _transfer(address from, address to, uint256 tokenId)
    internal virtual
    validTo(to) {
        // Before transfer checks
        _beforeTokenTransfer(from, to, tokenId, 1);
        // Set new owner
        __transfer(uint256(uint160(to)), tokenId);
        // Emit event
        emit Transfer(from, to, tokenId);
        // Update balances
        _afterTokenTransfer(from, to, 0, 1);
    }

    /**
     * @dev We have a separate function here because we don't want to read/write 
     * to balances for every token. One time update at the end only.
     */
    function _transfer(address from, address to, uint256[] calldata tokenIds)
    internal virtual
    validTo(to) {
        uint256 _to = uint256(uint160(to)); // Convert one time
        uint256 batchSize = tokenIds.length;
        uint256 tokenId;
        for (uint256 i; i<batchSize;) {
            tokenId = tokenIds[i];
            // Before transfer checks
            _beforeTokenTransfer(from, to, tokenId, 1);
            // Set new owner
            __transfer(_to, tokenId);
            // Emit event
            emit Transfer(from, to, tokenId);
            unchecked {++i;}
        }
        // Update balances one time
        _afterTokenTransfer(from, to, 0, batchSize);
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
                revert CallerNotOwnerOrApproved(tokenId, tokenOwner, _msgSender());
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
                    revert CallerNotOwnerOrApproved(tokenId, tokenOwner, _msgSender());
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
    validTo(tokenOwner)
    returns (uint256 balance) {
        (balance,,) = ownerDataOf(tokenOwner);
    }

    /**
     * @dev Batch version to clear approvals. To clear a single, 
     * pass in only one token, or set address to 0 using the 
     * approve method.
     */
    function clearApproved(uint256[] calldata tokenIds) external {
        uint256 _batchSize = tokenIds.length;
        for (uint256 i; i<_batchSize;) {
            if (!_isApprovedOrOwner(_msgSender(), tokenIds[i])) {
                revert CallerNotOwnerOrApproved(tokenIds[i], ownerOf(tokenIds[i]), _msgSender());
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
     * @dev Contract owner emits meta update for all tokens.
     */
    function metaUpdateAll()
    external virtual
    onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BatchMetadataUpdate(0, totalSupply());
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
    function safeTransferFrom(address from, address[] calldata to, uint256[][] calldata tokenIds)
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
    function setRoyaltyReceiver(address receiver)
    external virtual
    onlyRole(DEFAULT_ADMIN_ROLE)
    validTo(receiver)
    addressNotSame(_royaltyReceiver, receiver) {
        _royaltyReceiver = receiver;
    }

    /**
     * @dev Sets the contract wide royalties amount.
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

    function tokenCounter() 
    internal view virtual
    returns (uint256) {
        return _totalSupply;
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

    function transfersOf(address tokenOwner)
    public view virtual
    validTo(tokenOwner)
    returns (uint256 transfers) {
        (,transfers,) = ownerDataOf(tokenOwner);
    }

    function ownerDataOf(address tokenOwner)
    public view virtual
    returns (uint256 balance, uint256 transfers, uint256 redemptions) {
        uint256 ownerData = _balances[tokenOwner];
        balance = uint256(uint64(ownerData));
        transfers = uint256(ownerData>>192);
        redemptions = uint256(uint128(ownerData>>64));
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