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
contract ERC721 is C9Context, ERC165, IC9ERC721, IERC2981, IERC4906, C9OwnerControl {
    using Address for address;
    using Strings for uint256;

    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");

    uint256 constant APOS_LOCKED = 0;
    uint256 constant APOS_LOCKSTAMP = 8;
    uint256 constant APOS_LOCKPERIOD = 48;
    uint256 constant APOS_REGISTRATION = 72;
    uint256 constant APOS_RESERVED = 168;
    uint256 constant APOS_REDEMPTIONS = 176;
    uint256 constant APOS_BALANCE = 192;
    uint256 constant APOS_VOTES = 208;
    uint256 constant APOS_TRANSFERS = 232;

    uint256 constant MAX_LOCK_PERIOD = 1209600; // 14 days

    event Register(address indexed account);

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Total supply
    uint256 internal _totalSupply;

    // Total votes
    uint256 internal _totalVotes;
    
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

    bool private _reservedBalanceSpaceOpen;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint256 royalty) {
        name = name_;
        symbol = symbol_;
        _royalty = uint96(royalty);
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
     * This has been updated to add an on-chain transfer counters, which adds around ~700 gas per counter.
     * balance, votes, redemptions, transfers.
     *
     * This could have been placed in _transfer if not for stack too deep errors. So we've placed it here
     * instead.
     */
    function _afterTokenTransfer(address from, address to, uint256 /*firstTokenId*/, uint256 batchSize, uint256 votes)
    internal virtual {
        // Copy from storage first
        uint256 balancesFrom = _balances[from];
        // Check that the from account did not have an active lock
        if (uint256(uint8(balancesFrom)) == LOCKED) {
            revert AddressLocked(from);
        }
        // Copy from storage first
        uint256 balancesTo = _balances[to];
        // Parameters to update, token owners balances and transfer counts
        uint256 balanceFrom = uint256(uint16(balancesFrom>>APOS_BALANCE));
        uint256 votesFrom = uint256(uint24(balancesFrom>>APOS_VOTES));
        uint256 xfersFrom = balancesFrom>>APOS_TRANSFERS;
        uint256 balanceTo = uint256(uint16(balancesTo>>APOS_BALANCE));
        uint256 votesTo = uint256(uint24(balancesTo>>APOS_VOTES));
        uint256 xfersTo = balancesTo>>APOS_TRANSFERS;
        // Update balances and transfer counter
        unchecked {
            balanceFrom -= batchSize;
            votesFrom -= votes;
            xfersFrom += batchSize;
            balanceTo += batchSize;
            votesTo += votes;
            xfersTo += batchSize;
        }
        // Set packed data From in memory
        balancesFrom &= ~(MASK_BALANCER)<<APOS_BALANCE;
        balancesFrom |= balanceFrom<<APOS_BALANCE;
        balancesFrom |= votesFrom<<APOS_VOTES;
        balancesFrom |= xfersFrom<<APOS_TRANSFERS;
        // Set packed data Ro in memory
        balancesTo &= ~(MASK_BALANCER)<<APOS_BALANCE;
        balancesTo |= balanceTo<<APOS_BALANCE;
        balancesTo |= votesTo<<APOS_VOTES;
        balancesTo |= xfersTo<<APOS_TRANSFERS;
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
        _tokenApprovals[tokenId] = uint256(uint160(to));
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
     * @dev Updates the addresse's redemptions count.
     */
    function _addRedemptionsTo(address from, uint256 batchSize)
    internal view virtual {
        uint256 balancesFrom = _balances[from];
        uint256 redemptions = uint256(uint16(balancesFrom>>APOS_REDEMPTIONS));
        unchecked {
            redemptions += batchSize;
        }
        balancesFrom = _setTokenParam(
            balancesFrom,
            APOS_REDEMPTIONS,
            redemptions,
            type(uint16).max
        );
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
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
    internal virtual {}

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
     */
    function _isApproved(address spender, address tokenOwner, uint256 tokenId)
    internal view virtual
    returns (bool) {
        return (isApprovedForAll(tokenOwner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     */
    function _isApprovedOrOwner(address spender, address tokenOwner, uint256 tokenId)
    internal view virtual {
        if (spender != tokenOwner) {
            if (!_isApproved(spender, tokenOwner, tokenId)) {
                revert CallerNotOwnerOrApproved(tokenId, tokenOwner, spender);
            }
        }
    }




    function _mint(address to, uint256 firstTokenId, uint256 batchSize)
    internal virtual {
        uint256 _to = uint256(uint160(to));
        uint256 _tokenIdLast = firstTokenId+batchSize;
        uint256 _tokenId = firstTokenId;
        for (_tokenId; _tokenId<_tokenIdLast;) {
            if (_exists(_tokenId)) {
                revert TokenAlreadyMinted(_tokenId);
            }
            _owners[_tokenId] = _to<<MPOS_OWNER;
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
        return address(uint160(_owners[tokenId]>>MPOS_OWNER));
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
     * Updated to impose restriction on _msgSender() since this is 
     * called singular or batched. The restriction on to 
     * is called from the wrapper of this.
     *
     * The goal of this method is to read from _owners only 
     * one time, do all checks and updates necessary in memory, 
     * and then copy back to storage one time per tokenId, 
     * making it extendable to batching.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */

    function __transfer(address from, uint256 to, uint256 tokenId)
    internal virtual
    notFrozen()
    returns (uint256 votes) {
        uint256 tokenData = _owners[tokenId];
        /*
        1. Make sure from is correct owner.
           This also implicitly enforces the token existing or not being burned,
           because the zero address will never have any approvals set.
        */
        address tokenOwner = address(uint160(tokenData>>MPOS_OWNER));
        if (tokenOwner != from) {
            revert TransferFromIncorrectOwner(tokenOwner, from);
        }
        // 2. Make sure the caller is owner or approved
        if (_msgSender() != tokenOwner) {
            if (!_isApproved(_msgSender(), tokenOwner, tokenId)) {
                revert CallerNotOwnerOrApproved(tokenId, tokenOwner, _msgSender());
            }
        }
        // 3. Make sure token is not locked
        if (tokenData & BOOL_MASK == LOCKED) {
            revert TokenIsLocked(tokenId);
        }
        // 4. If the token is inactive, automatically update to be active (~210 gas cost when active)
        if (_viewPackedData(tokenData, MPOS_VALIDITY, MSZ_VALIDITY) == INACTIVE) {
            tokenData = _setDataValidity(tokenData, VALID);
        }
        /*
        5. Clear approvals from the previous owner.
           The if statement saves ~200 gas when no approval is set (most users).
        */
        if (_tokenApprovals[tokenId] != 0) {
            delete _tokenApprovals[tokenId];
        }

        uint256 tokenTransferCount = tokenData>>MPOS_XFER_COUNTER;
        unchecked {++tokenTransferCount;}
        votes = _viewPackedData(tokenData, MPOS_VOTES, MSZ_VOTES);

        // Set new owner and transfer count
        tokenData &= ~(MASK_ADDRESS_XFER)<<MPOS_OWNER;
        tokenData |= to<<MPOS_OWNER;
        tokenData |= tokenTransferCount<<MPOS_XFER_COUNTER;

        // Copy back to storage
        _owners[tokenId] = tokenData;
    }

    function _transfer(address from, address to, uint256 tokenId)
    internal virtual
    validTo(to) {
        // Checks, set new owner, return votes to add to balances
        uint256 votes = __transfer(from, uint256(uint160(to)), tokenId);
        // Update balances
        _afterTokenTransfer(from, to, 0, 1, votes);
        // Emit event
        emit Transfer(from, to, tokenId);
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
        uint256 votes;
        for (uint256 i; i<batchSize;) {
            tokenId = tokenIds[i];
            // Set new owner
            unchecked {votes += __transfer(from, _to, tokenId);}
            // Emit event
            emit Transfer(from, to, tokenId);
            unchecked {++i;}
        }
        // Update balances one time
        _afterTokenTransfer(from, to, 0, batchSize, votes);
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId)
    public virtual
    override
    validTo(to) {
        address tokenOwner = ownerOf(tokenId);
        if (to == tokenOwner) {
            revert OwnerAlreadyApproved();
        }
        _isApprovedOrOwner(_msgSender(), tokenOwner, tokenId);
        _approve(to, tokenId);
    }

    function approve(address[] calldata to, uint256[][] calldata tokenIds)
    external virtual {
        uint256 _batchSize = tokenIds.length;
        uint256 _addressBookSize = to.length;
        if (_addressBookSize != _batchSize) {
            revert TransferSizeMismatch(_addressBookSize, _batchSize);
        }
        uint256 tokenId;
        uint256 _tokenIdsBatchSize;
        for (uint256 i; i<_batchSize;) {
            _tokenIdsBatchSize = tokenIds[i].length;
            for (uint256 j; j<_tokenIdsBatchSize;) {
                tokenId = tokenIds[i][j];
                approve(to[i], tokenId);
                unchecked {++j;}
            }
            unchecked {++i;}
        }
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address tokenOwner)
    public view virtual
    override
    returns (uint256 balance) {
        (balance,,,) = ownerDataOf(tokenOwner);
    }

    /**
     * @dev Batch version to clear approvals. To clear a single, 
     * pass in only one token, or set address to 0 using the 
     * approve method.
     */
    function clearApproved(uint256[] calldata tokenIds) external {
        uint256 _batchSize = tokenIds.length;
        uint256 _tokenId;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            _isApprovedOrOwner(_msgSender(), ownerOf(_tokenId), _tokenId);
            delete _tokenApprovals[_tokenId];
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
     * @dev Gets the stored registration data.
     */
    function getRegistrationFor(address account)
    external view
    onlyRole(REDEEMER_ROLE)
    returns (uint256 data) {
        if (!isRegistered(account)) {
            revert AddressNotRegistered(account);
        }
        return uint256(uint96(_balances[account]>>APOS_REGISTRATION));
    }

    /**
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function getReservedBalanceSpace(address account)
    external view
    returns (uint256) {
        uint256 balanceData = _balances[account];
        return uint256(uint8(balanceData>>APOS_RESERVED));
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
     * @dev Returns if the account has registered.
     */
    function isRegistered(address account)
    public view
    returns (bool) {
        return uint96(_balances[account]>>APOS_REGISTRATION) > 0;
    }

    /**
     * @dev Contract owner emits meta update for all tokens.
     */
    function metaUpdateAll()
    external virtual
    onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /**
     * @dev View function to see owner balances data.
     */
    function ownerDataOf(address tokenOwner)
    public view virtual
    returns (uint256 balance, uint256 votes, uint256 redemptions, uint256 transfers) {
        uint256 ownerData = _balances[tokenOwner];
        balance = uint256(uint16(ownerData>>APOS_BALANCE));
        votes = uint256(uint24(ownerData>>APOS_VOTES));
        redemptions = uint256(uint16(ownerData>>APOS_REDEMPTIONS));
        transfers = uint256(ownerData>>APOS_TRANSFERS);
    }

    /**
     * @dev View function to see owner lock status.
     */
    function ownerLocked(address tokenOwner)
    public view virtual
    returns (bool locked, uint256 lockStamp) {
        uint256 ownerData = _balances[tokenOwner];
        uint256 _locked = uint256(uint8(ownerData));
        locked = _locked == 1 ? true : false;
        lockStamp = uint256(uint40(ownerData>>APOS_LOCKSTAMP));
    }

    /**
     * @dev See {IERC721-ownerOf}.
     * Note: Prior ownerOf reverts is the owner address (0) meaning 
     * the token doesn't exist. Since this ERC stores additional 
     * data in tokenId, we need to check if any data is present 
     * to ensure the token is invalid. This checks only happens 
     * if tokenOwner is address(0) to save on gas.
     */
    function ownerOf(uint256 tokenId)
    public view virtual
    override
    returns (address) {
        address tokenOwner = _ownerOf(tokenId);
        if (tokenOwner == address(0)) {
            if (!_exists(tokenId)) {
                revert InvalidToken(tokenId);
            }
        }
        return tokenOwner;
    }

    function redemptionsOf(address tokenOwner)
    public view virtual
    returns (uint256 redemptions) {
        (,,redemptions,) = ownerDataOf(tokenOwner);
    }

    /**
     * @dev Adds address registration.
     */
    function register(bytes32 ksig32)
    external
    notFrozen() {
        _balances[_msgSender()] = _setTokenParam(
            _balances[_msgSender()],
            APOS_REGISTRATION,
            uint96(bytes12(ksig32)),
            type(uint96).max
        );
        emit Register(_msgSender());
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
    function safeTransferBatchFrom(address from, address to, uint256[] calldata tokenIds)
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
    function safeBatchTransferBatchFrom(address from, address[] calldata to, uint256[][] calldata tokenIds)
    external {
        uint256 _batchSize = tokenIds.length;
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
     * @dev Sets the data for the reserved (unused balance) 
     * space. Since this storage is already paid for, it may
     * be used for expansion features that may be available 
     * later. Such features will only be available to 
     * external contracts, as this contract will have no
     * built-in parsing.
     * 8 bits remain in the reserved storage space.
     */
    function setReservedBalanceSpace(uint256 data)
    external {
        if (!_reservedBalanceSpaceOpen) {
            revert ReservedSpaceNotOpen();
        }
        _balances[_msgSender()] = _setTokenParam(
            _balances[_msgSender()],
            APOS_RESERVED,
            data,
            type(uint8).max
        );
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

    /**
     * @dev Flag that sets global toggle to freeze redemption. 
     * Users may still cancel redemption and unlock their 
     * token if in the process.
     */
    function toggleReservedBalanceSpace(bool toggle)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_reservedBalanceSpaceOpen == toggle) {
            revert BoolAlreadySet();
        }
        _reservedBalanceSpaceOpen = toggle;
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

    function totalVotes()
    public view virtual 
    returns (uint256) {
        return _totalVotes;
    }

    function transfersOf(address tokenOwner)
    public view virtual
    returns (uint256 transfers) {
        (,,,transfers) = ownerDataOf(tokenOwner);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId)
    public virtual {
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Allows batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Max batch size is 64.
     */
    function transferBatchFrom(address from, address to, uint256[] calldata tokenIds)
    external virtual
    override {
        _transfer(from, to, tokenIds);
    }

    /**
     * @dev Allows user to temporarily lock all tokens from being
     * transferred.
     */
    function userLockAddress(uint256 lockPeriod)
    external virtual {
        if (lockPeriod == 0) {
            revert ZeroValueError();
        }
        if (lockPeriod > MAX_LOCK_PERIOD) {
            revert PeriodTooLong(MAX_LOCK_PERIOD, lockPeriod);
        }
        // Check that the from account does not already have an active lock
        uint256 addressInfo = _balances[_msgSender()];
        if (uint256(uint8(addressInfo)) == LOCKED) {
            revert AddressLocked(_msgSender());
        }
        // Set the account lock
        addressInfo = _setTokenParam(
            addressInfo,
            APOS_LOCKED,
            LOCKED,
            type(uint8).max
        );
        // Set the account lock timestamp
        addressInfo = _setTokenParam(
            addressInfo,
            APOS_LOCKSTAMP,
            block.timestamp,
            type(uint40).max
        );
        // Set the account lock period timestamp
        addressInfo = _setTokenParam(
            addressInfo,
            APOS_LOCKPERIOD,
            lockPeriod,
            type(uint24).max
        );
        // Write back to storage
        _balances[_msgSender()] = addressInfo;
    }

    /**
     * @dev Allows user to unlock all tokens (if locked, and 
     * if lock period has expired).
     */
    function userUnlockAddress()
    external virtual {
        uint256 addressInfo = _balances[_msgSender()];
        // Check that the from account does not already have an active lock
        if (uint256(uint8(addressInfo)) == UNLOCKED) {
            revert AddressNotLocked();
        }
        // Check the lock period has expired
        uint256 _userLockPeriod =  uint256(uint24(addressInfo>>APOS_LOCKPERIOD));
        uint256 _sinceLocked = block.timestamp - uint256(uint40(addressInfo>>APOS_LOCKSTAMP));
        if (_sinceLocked < _userLockPeriod) {
            revert LockPeriodNotFinished(_userLockPeriod, _sinceLocked);
        }
        // Set the account unlocked
        addressInfo = _setTokenParam(
            addressInfo,
            APOS_LOCKED,
            UNLOCKED,
            type(uint8).max
        );
        // No need to update lock timestamp
        // Write back to storage
        _balances[_msgSender()] = addressInfo;
    }

    function votesOf(address tokenOwner)
    public view virtual
    returns (uint256 votes) {
        (,votes,,) = ownerDataOf(tokenOwner);
    }
}