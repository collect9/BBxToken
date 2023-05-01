// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9Token6.sol";

import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Redeemable is C9Token {
    
    uint256 constant RPOS_BATCHSIZE = 0; // Pending number of redemptions, max 6, 3-bits data needed
    uint256 constant RPOS_FEES_PAID = 3; // 13-bits max value 8191, making max usable value here 999
    uint256 constant RPOS_TOKEN1 = 16;
    uint256 constant MAX_BATCH_SIZE = 6;

    uint256 constant RFEES_SIZE = 13;
    uint256 constant RUINT_SIZE = 24;

    uint256 private _baseFees;
    bool private _frozenRedeemer;
    address private contractPricer;
    uint256 public preRedeemablePeriod; //seconds
    uint24[] private _redeemedTokens;

    /**
     * @dev https://docs.opensea.io/docs/metadata-standards.
     * @notice While there is no definitive EIP yet for token staking or locking, OpenSea 
     * does support several events to help signal that a token should not be eligible 
     * for trading. This helps prevent "execution reverted" errors for your users 
     * if transfers are disabled while in a staked or locked state.
     */
    event TokenLocked(uint256 indexed tokenId, address indexed approvedContract);
    event TokenUnlocked(uint256 indexed tokenId, address indexed approvedContract);

    constructor() {
        _baseFees = 20;
        preRedeemablePeriod = 31600000; //1 year
    }

    /*
     * @dev Checks to see contract is not frozen.
     */ 
    modifier redeemerNotFrozen() { 
        if (_frozenRedeemer) {
            revert RedeemerFrozen();
        }
        _;
    }

    /**
     * @dev Updates the address redemptions count.
     * @param redeemer The address to increment redemptions count of.
     * @param batchSize The increment amount.
     */
    function _addRedemptionsTo(address redeemer, uint256 batchSize)
    internal virtual {
        uint256 balancesFrom = _balances[redeemer];
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
        _balances[redeemer] = balancesFrom;
    }

    /*
     * @dev Checks to see if the caller is approved for the redeemer.
     * @param redeemer The address of the account to check if _msgSender() is 
     * approved on behalf of.
     */ 
    function _callerApproved(address redeemer)
    private view {
        if (_msgSender() != redeemer) {
            if (!isApprovedForAll(redeemer, _msgSender())) {
                revert Unauthorized();
            }
        }
    }
    
    /*
     * @dev Clears the step, batchsize, and space for 6x u24 tokenIds.
     * @param redeemer The address to clear any redemption data of.
     * @notice The first 160 bits of the balances data are the redeemer data.
     */
    function _clearRedemptionData(address redeemer)
    private {
        _balances[redeemer] &= ~(uint256(type(uint160).max));
    }

    /*
     * @dev Gets the tokenIds batch size of the redeemer.
     * @param redeemerData _balances[address].
     */
    function _getBatchSize(uint256 redeemerData)
    private pure
    returns (uint256) {
        return _viewPackedData(redeemerData, 0, 3);
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * While the IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup, and the contract 
     * supports interface may be updated in the future to signal
     * support.
     * @param tokenId The tokenId.
     * @param ownersData _owners[tokenId].
     */
    function _isRedeemable(uint256 tokenId, uint256 ownersData)
    private view
    returns (bool) {
        if (_preRedeemable(_uTokenData[tokenId])) {
            return false;
        }
        uint256 _vId = _currentVId(ownersData); 
        if (_vId != VALID) {
            if (_vId != INACTIVE) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Locks the token from further transfer.
     * @param tokenId The tokenId.
     * @param ownersData _owners[tokenId].
     * @return uint256 The updated ownersData of tokenId locked.
     */
    function _lockToken(uint256 tokenId, uint256 ownersData)
    internal
    returns (uint256) {
        emit TokenLocked(tokenId, _msgSender());
        return ownersData |= BOOL_MASK<<MPOS_LOCKED;
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     * @param tokenData _uTokenData[tokenId].
     * @return bool If the token pre-release period has ended.
     */
    function _preRedeemable(uint256 tokenData)
    private view
    returns (bool) {
        uint256 _ds = block.timestamp - _viewPackedData(tokenData, UPOS_MINTSTAMP, USZ_TIMESTAMP);
        return _ds < preRedeemablePeriod;
    }

    /*
     * @dev Locks the tokens after a series of conditions pass.
     * @param tokenIds The array of tokenId to lock.
     */
    function _redeemLockTokens(uint256[] calldata tokenIds)
    private {
        uint256 _batchSize = tokenIds.length;
        uint256 _tokenId;
        uint256 _ownerData;
        address _redeemer;
        for (uint256 i; i<_batchSize;) {
            // 1. Get the tokenId
            _tokenId = tokenIds[i];
            // 2. Copy the token's tightly packed data from storage
            _ownerData = _owners[_tokenId];
            // 3. Check _msgSender() is owner or approved of the tokenId
            _redeemer = address(uint160(_ownerData>>MPOS_OWNER));
            _isApprovedOrOwner(_msgSender(), _redeemer, _tokenId);
            // 4. Check token is redeemable
            if (!_isRedeemable(_tokenId, _ownerData)) {
                revert TokenNotRedeemable(_tokenId);
            }
            /* 5. If redeemable but locked, the token is already in redeemer.
                  This will also prevent multiple approved users trying to
                  redeem the same token at once.
            */
            if (_isLocked(_ownerData)) {
                revert TokenIsLocked(_tokenId);
            }
            // 6. All checks pass, so lock the token
            _ownerData = _lockToken(_tokenId, _ownerData);
            // 7. Save to storage (token now locked)
            _owners[_tokenId] = _ownerData;
            unchecked {++i;}
        }
    }

    /**
     * @dev Updates the token validity status. If the validity status
     * is set to be a dead status (REDEEMED or greater) then the token is 
     * locked. If set to redeemed the token is locked and a redemption 
     * is added to the owner of that token.
     * @param tokenId The tokenId.
     * @param ownersData _owners[tokenId].
     * @param vId The integer validity status to set for tokenId.
     * @notice Emits an event so marketplaces supporting ERC4906 will 
     * quickly show the updated status.
     */
    function _setTokenValidity(uint256 tokenId, uint256 ownersData, uint256 vId)
    internal {
        ownersData = _setDataValidity(ownersData, vId);
        // Lock if changing to a dead status (forever lock)
        if (vId >= REDEEMED) {
            ownersData = _lockToken(tokenId, ownersData);
            if (vId == REDEEMED) {
                _redeemedTokens.push(uint24(tokenId));
                _addRedemptionsTo(_ownerOf(tokenId), 1);
            }
        }
        _owners[tokenId] = ownersData;
        _metaUpdate(tokenId);
    }

    /**
     * @dev Unlocks the token.
     * @param tokenId The tokenId to unlock.
     * @notice Emits an event so supporting marketplaces know to 
     * re-enable exchange of this tokenId.
     */
    function _unlockToken(uint256 tokenId)
    internal {
        _owners[tokenId] &= ~(BOOL_MASK<<MPOS_LOCKED);
        emit TokenUnlocked(tokenId, _msgSender());
    }

    /**
     * @dev Unpacks tokenIds from the tightly packed
     * redemption data.
     * @param redeemerData _balances[address].
     * @return tokenIds The unpacked array of tokenId.
     */
    function _unpackTokenIds(uint256 redeemerData)
    private pure
    returns (uint256[] memory tokenIds) {
        uint256 _batchSize = _getBatchSize(redeemerData);
        tokenIds = new uint256[](_batchSize);
        uint256 _packedOffset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            tokenIds[i] = uint256(uint24(redeemerData>>_packedOffset));
            unchecked {
                _packedOffset += RUINT_SIZE;
                ++i;
            }
        }
    }

    /**
     * @dev Admin clear redeemer slot.
     * @param redeemer Address to clear (zero out) all redeemer data.
     */
    function adminClearRedeemer(address redeemer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        _clearRedemptionData(redeemer);
    }

    /**
     * @dev Admin final approval of tokens to be redeemed.
     * @param redeemer The account of the redeemer to approve.
     * The tokenIds within that redeemer's data will be set 
     * to status REDEEMED.
     */
    function adminFinalApprove(address redeemer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        // 1. Make sure redeemer is on last step
        uint256 _redeemerData = _balances[redeemer];
        uint256 _batchSize = _getBatchSize(_redeemerData);
        if (_batchSize == 0) {
            revert WrongProcessStep(2, 0);
        }
        // 2. Get tokenIds for this redeemer
        uint256[] memory _tokenIds = _unpackTokenIds(_redeemerData);
        // 3. Set all tokens in the redeemer's account to redeemed
        uint256 _tokenId;
        for (uint256 i; i<_batchSize;) {
            _tokenId = _tokenIds[i];
            _owners[_tokenId] = _setDataValidity(_owners[_tokenId], REDEEMED);
            unchecked {++i;}
        }
        // 4. To to redeemer's redemption count
        _addRedemptionsTo(_ownerOf(_tokenIds[0]), _batchSize);
        // 5. Clear redeemer's info so a new redemption can begin
        _clearRedemptionData(redeemer);
    }

    /**
     * @dev Fail-safe function that can unlock an active status token.
     * This is for any edge cases that may have been missed 
     * during testing.
     * Dead tokens are still not possible to unlock, though they 
     * may still be burned (to the zero address only, so the token 
     * still exists without present and future owner).
     * @param tokenId the tokenId to unlock.
     */
    function _adminUnlock(uint256 tokenId)
    private
    requireMinted(tokenId)
    notDead(tokenId) {
        _unlockToken(tokenId);
    }

    /**
     * @dev Batched version of _adminUnlock to save on gas fees.
     * @param tokenIds The array of tokenId to unlock.
     */
    function adminUnlock(uint256[] calldata tokenIds)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 _batchSize = tokenIds.length;
        for (uint256 i; i<_batchSize;) {
            _adminUnlock(tokenIds[i]);
            unchecked {++i;}
        }
    }

    /**
     * @dev Convenience view function.
     */
    function getContracts()
    external view
    override
    returns(address meta, address pricer, address upgrader, address vH) {
        meta = contractMeta;
        pricer = contractPricer;
        upgrader = contractUpgrader;
        vH = contractVH;
    }

    /**
     * @dev Convenience view function.
     * @return redeemedTokens The array of redeemed tokenId.
     */
    function getRedeemed()
    external view
    returns (uint24[] memory redeemedTokens) {
        redeemedTokens = _redeemedTokens;
    }

    /*
     * @dev Returns the s&h fees payable given redemption batch size.
     * @param insuredValue The insured value in USD.
     * @return total Fees payable in USD.
     */
    function getRedemptionFees(uint256 insuredValue)
    public view
    returns (uint256 total) {
        uint256 baseFees = _baseFees;
        unchecked {
            total = baseFees + baseFees*insuredValue/1000;
        }
    }

    /*
     * @dev Convenience view function.
     * @param redeemer The address of the redeemer to lookup.
     * @return tokenIds The array of tokenIds for the redeemer.
     */
    function getRedeemerTokenIds(address redeemer)
    external view
    returns(uint256[] memory tokenIds) {
        uint256 _balancesData = _balances[redeemer];
        tokenIds = _unpackTokenIds(_balancesData);
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * The IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup.
     * @param tokenId The tokenId.
     * @return bool If the tokenId is redeemable.
     */
    function isRedeemable(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _ownerData = _owners[tokenId];
        return _isRedeemable(tokenId, _ownerData);
    }

    /**
     * @dev Convenience view function.
     * @param tokenId The tokenId.
     * @return If a token is already redeemed.
     */
    function isRedeemed(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _ownerData = _owners[tokenId];
        return _currentVId(_ownerData) == REDEEMED;
    }

    /**
     * @dev Convenience view function.
     * @param tokenId The tokenId.
     * @return Whether or not the tokenId pre-release period 
     * has ended.
     */
    function preRedeemable(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _tokenData = _uTokenData[tokenId];
        return _preRedeemable(_tokenData);
    }

    /**
     * @dev Allows user to cancel redemption while pending 
     * final admin approval. There is no built-in auto refund.
     *
     * @param redeemer Address of tokens to unlock
     */
    function redeemCancel(address redeemer)
    external payable {
        // 1. Check if caller approved
        _callerApproved(redeemer);
        // 2. Check if redemption batch exists
        uint256 _redeemerData = _balances[redeemer];
        uint256 _batchSize = _getBatchSize(_redeemerData);
        if (_batchSize == 0) {
            revert NoRedemptionBatchPresent();
        }
        // 3. Unlock all tokens in redeemer
        uint256[] memory _tokenIds = _unpackTokenIds(_redeemerData);
        for (uint256 i; i<_batchSize;) {
            _unlockToken(_tokenIds[i]);
            unchecked {++i;}
        }
        // 4. Get refund amount
        uint256 _redemptionFees = _viewPackedData(_redeemerData, RPOS_FEES_PAID, RFEES_SIZE);
        // 5. Clear redeemer data
        _clearRedemptionData(redeemer);
        /* 6. Process refund after all other state vars are set.
              It should not be possible to re-enter this function and reach 
              this point again as _batchSize should be zero after re-entry.
        */
        if (_redemptionFees > 0) {
            uint256 _refundFeesWei = _redemptionFees * 10**15; // converts 0.xxx eth into wei
            _transferFunds(redeemer, _refundFeesWei);
        }
    }
    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     * @param redeemer The address to start the redemption process for
     * @param registrationCode The correct registration code received by 
     * the redeemer upon registration.
     * @param tokenIds The array of tokenId to redeem.
     * @notice Max length of tokenIds due to tightly packed
     * storage limitations. Some code has been moved to a separate 
     * internal function to prevent stack to deep errors.
     */
    function redeemStart(address redeemer, uint256 registrationCode, uint256[] calldata tokenIds)
    external payable
    redeemerNotFrozen() {
        // 1. Checks
        _callerApproved(redeemer);
        uint256 _redeemerData = _balances[redeemer];
        // 1b. Check the account is already registered
        uint256 _registrationData = _getRegistrationFor(_redeemerData);
        if (_registrationData == 0) {
            revert AddressMustFirstRegister(redeemer);
        }
        // 1c. Check registration code
        if (registrationCode != _registrationData) {
            revert CodeMismatch();
        }
        // 1d. Check account does not have a pending redemption
        uint256 _batchSize = _getBatchSize(_redeemerData);
        if (_batchSize > 0) {
            revert WrongProcessStep(0, 2);
        }
        // 1e. Check redemption batchsize is within limits
        _batchSize = tokenIds.length;
        if (_batchSize > MAX_BATCH_SIZE) {
            revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
        }
        // 2. Lock tokens
        _redeemLockTokens(tokenIds);
        // 3. Get the estimated s&h fees
        uint256 _insuredValue = getInsuredsValue(tokenIds);
        uint256 _feesUSD = getRedemptionFees(_insuredValue);
        uint256 _redemptionFees; // Min value 0
        // Check if >0 (i.e. some promotions may set baseFees to 0)
        if (_feesUSD > 0) {       
            uint256 _feesWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(
                _feesUSD
            );
            // 4. Make sure payment amount is valid
            if (msg.value != _feesWei) {
                revert InvalidPaymentAmount(_feesWei, msg.value);
            }
            // 5. Make sure payment is successful
            _sendPayment(_msgSender(), address(this), msg.value);
            // 6. Get fee amount to store in redeemer's data
            _redemptionFees = (_feesWei-1) / (10**15); // Max value 999 or 0.999 ETH
        }
        // 5. Update redeemer data
        _redeemerData |= _batchSize<<RPOS_BATCHSIZE;
        _redeemerData |= _redemptionFees<<RPOS_FEES_PAID;
        uint256 _offset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            _redeemerData |= tokenIds[i]<<_offset;
            unchecked {
                _offset += RUINT_SIZE;
                ++i;
            }
        }
        // 6. Save redeemer state
        _balances[redeemer] = _redeemerData;
    }

    /**
     * @dev Sets the base shipping fee.
     * @param baseFees The new base shipping fee.
     */
    function setBaseFees(uint256 baseFees)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (baseFees == _baseFees) {
            revert ValueAlreadySet();
        }
        _baseFees = baseFees;
    }

    /**
     * @dev Sets the eth pricer contract address.
     * @param pricer The new contract address.
     */
    function setContractPricer(address pricer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    addressNotSame(contractPricer, pricer) {
        contractPricer = pricer;
    }

    /**
     * @dev Sets the global token redeemable period.
     * @param period The new pre-redeemable period.
     */
    function setPreRedeemPeriod(uint256 period)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (preRedeemablePeriod == period) {
            revert ValueAlreadySet();
        }
        preRedeemablePeriod = period;
    }

    /*
     * @dev Sets the token validity.
     * @param tokenId The tokenId.
     * @param vId The new validity status id to set.
     */
    function setTokenValidity(uint256 tokenId, uint256 vId)
    external
    onlyRole(VALIDITY_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
        uint256 _ownersData = _owners[tokenId];
        uint256 _tokenValidity = _currentVId(_ownersData);
        if (vId == _tokenValidity) {
            revert ValueAlreadySet();
        }
        if (vId > REDEEMED) {
            // Cannot go from a VALID (0) status immediately to DEAD (>4)
            if (_tokenValidity == VALID) {
                revert CannotValidToDead(tokenId, vId);
            }
        }
        _setTokenValidity(tokenId, _ownersData, vId);
    }

    /**
     * @dev Freezes or unfreezes redeemer portion of contract.
     * @param toggle Freeze (true) or unfreeze (false).
     */
    function toggleRedeemerFreezer(bool toggle)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozenRedeemer == toggle) {
            revert BoolAlreadySet();
        }
        _frozenRedeemer = toggle;
    }

    /**
     * @dev Convenience view function.
     * @return uint256 The total number of redeemed tokens.
     */
    function totalRedeemed()
    external view
    returns (uint256) {
        return _redeemedTokens.length;
    }

    /**
     * @dev Withdrawal function to remove partial or entire 
     * contract balance.
     */
    function withdraw(address account, uint256 amount)
    external
    onlyRole(DEFAULT_OWNER_ROLE) {
        uint256 _thisBalance = address(this).balance;
        // 1. Check amount is valid
        if (amount > _thisBalance) {
            revert WithdrawlExceedsBalance();
        }
        // 2. Check amount to remove
        if (amount == 0) { // Remove full balance
            _transferFunds(account, address(this).balance);
        }
        else { // Remove partial
            _transferFunds(account, amount);
        }
    }
}