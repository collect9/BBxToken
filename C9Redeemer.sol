// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9Token6.sol";

import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Redeemable is C9Token {
    
    uint256 constant RPOS_STEP = 0;
    uint256 constant RPOS_BATCHSIZE = 8; // Pending number of redemptions
    uint256 constant RPOS_TOKEN1 = 16;
    uint256 constant MAX_BATCH_SIZE = 6;
    uint256 constant RUINT_SIZE = 24;

    bool private _frozenRedeemer;
    address private contractPricer;
    uint256 public preRedeemablePeriod; //seconds
    uint24[] private _redeemedTokens;

    /**
     * @dev https://docs.opensea.io/docs/metadata-standards.
     * While there is no definitive EIP yet for token staking or locking, OpenSea 
     * does support several events to help signal that a token should not be eligible 
     * for trading. This helps prevent "execution reverted" errors for your users 
     * if transfers are disabled while in a staked or locked state.
     */
    event TokenLocked(uint256 indexed tokenId, address indexed approvedContract);
    event TokenUnlocked(uint256 indexed tokenId, address indexed approvedContract);

    constructor() {
        preRedeemablePeriod = 31600000; //1 year
    }

    /*
     * @dev Check to see if contract is frozen.
     */ 
    modifier redeemerNotFrozen() { 
        if (_frozenRedeemer) {
            revert RedeemerFrozen();
        }
        _;
    }

    /*
     * @dev Checks to see if the caller is approved for 
     * the redeemer.
     */ 
    function _callerApproved(address tokenOwner)
    private view {
        if (_msgSender() != tokenOwner) {
            if (!isApprovedForAll(tokenOwner, _msgSender())) {
                revert Unauthorized();
            }
        }
    }

    /*
     * @dev Checks batch size and that redeemer is not too
     * far along in the process to still make changes.
     */ 
    function _changeChecker(uint256 balancesData)
    private pure
    returns (uint256 _originalBatchSize) {
        // 1. Check a batch size exists
        _originalBatchSize = _getBatchSize(balancesData);
        _checkBatchSize(_originalBatchSize);
        // 2. Make sure redeemer is not already at final step
        uint256 _currentStep = _getStep(balancesData);
        if (_currentStep > 2) {
            revert AddressToFarInProcess(2, _currentStep);
        }
    }

    /*
     * @dev Checks batch size.
     */ 
    function _checkBatchSize(uint256 batchSize)
    private pure {
        if (batchSize == 0) {
            revert NoRedemptionBatchPresent();
        }
    }

    /*
     * @dev Clears the step, batchsize, and space for 
     * 6 token Ids (u24).
     */
    function _clearRedemptionData(address redeemer)
    private {
        _balances[redeemer] &= ~(uint256(type(uint160).max));
    }

    /*
     * @dev Gets the batch size of the redeemer.
     */
    function _getBatchSize(uint256 balancesData)
    private pure
    returns (uint256) {
        return uint256(uint8(balancesData>>RPOS_BATCHSIZE));
    }

    /*
     * @dev Gets the step of the redeemer.
     */
    function _getStep(uint256 balancesData)
    private pure
    returns (uint256) {
        return uint256(uint8(balancesData));
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * The IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup.
     */
    function _isRedeemable(uint256 tokenId, uint256 tokenData)
    private view
    returns (bool) {
        if (_preRedeemable(_uTokenData[tokenId])) {
            return false;
        }
        uint256 _vId = _currentVId(tokenData); 
        if (_vId != VALID) {
            if (_vId != INACTIVE) {
                return false;
            }
        }
        return true;
    }

    function _lockToken(uint256 tokenId, uint256 tokenData)
    internal
    returns (uint256) {
        emit TokenLocked(tokenId, _msgSender());
        return tokenData |= BOOL_MASK<<MPOS_LOCKED;
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function _preRedeemable(uint256 tokenData)
    private view
    returns (bool) {
        uint256 _ds = block.timestamp - _viewPackedData(tokenData, UPOS_MINTSTAMP, USZ_TIMESTAMP);
        return _ds < preRedeemablePeriod;
    }

    /*
     * @dev The function that locks to token prior to 
     * calling the redeemer contract.
     */
    function _redeemLockTokens(uint256[] calldata tokenIds)
    private {
        uint256 _batchSize = tokenIds.length;
        uint256 _tokenId;
        uint256 _ownerData;
        address _tokenOwner;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            // 1. Copy token data from storage
            _ownerData = _owners[_tokenId];
            // 2. Check caller is owner or approved
            _tokenOwner = address(uint160(_ownerData>>MPOS_OWNER));
            _isApprovedOrOwner(_msgSender(), _tokenOwner, _tokenId);
            // 3. Check token is redeemable
            if (!_isRedeemable(_tokenId, _ownerData)) {
                revert TokenNotRedeemable(_tokenId);
            }
            /* 4. If redeemable but locked, token is already in redeemer.
                  This will also prevent multiple approved trying to
                  redeem the same token at once.
            */
            if (_isLocked(_ownerData)) {
                revert TokenIsLocked(_tokenId);
            }
            // 5. All checks pass, so lock the token
            _ownerData = _lockToken(_tokenId, _ownerData);
            // 6. Save to storage
            _owners[_tokenId] = _ownerData;
            unchecked {++i;}
        }
    }

    /*
     * @dev Checks to make sure user is on correct redemption step.
     */ 
    function _redemptionStep(uint256 redeemerData, uint256 step)
    private pure {
        uint256 _expected = _getStep(redeemerData);
        if (step != _expected) {
            revert WrongProcessStep(_expected, step);
        }
    }

    /**
     * @dev Updates the token validity status.
     */
    function _setTokenValidity(uint256 tokenId, uint256 tokenData, uint256 vId)
    internal {
        tokenData = _setDataValidity(tokenData, vId);
        // Lock if changing to a dead status (forever lock)
        if (vId >= REDEEMED) {
            tokenData = _lockToken(tokenId, tokenData);
            if (vId == REDEEMED) {
                _redeemedTokens.push(uint24(tokenId));
                _addRedemptionsTo(_ownerOf(tokenId), 1);
            }
        }
        _owners[tokenId] = tokenData;
        _metaUpdate(tokenId);
    }

    /**
     * @dev Unlocks the token. The Redeem cancel functions 
     * call this to unlock the token.
     */
    function _unlockToken(uint256 _tokenId)
    internal {
        _owners[_tokenId] &= ~(BOOL_MASK<<MPOS_LOCKED);
        emit TokenUnlocked(_tokenId, _msgSender());
    }

    /**
     * @dev Unpacks tokenIds from the tightly packed
     * redemption data portion of the balances slot.
     */
    function _unpackTokenIds(uint256 balancesData)
    private pure
    returns (uint256[] memory tokenIds) {
        uint256 _batchSize = _getBatchSize(balancesData);
        tokenIds = new uint256[](_batchSize);
        uint256 _packedOffset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            tokenIds[i] = uint256(uint24(balancesData>>_packedOffset));
            unchecked {
                _packedOffset += RUINT_SIZE;
                ++i;
            }
        }
    }

    /**
     * @dev Admin clear redeemer slot.
     */
    function adminClearRedeemer(address redeemer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        _clearRedemptionData(redeemer);
    }

    /**
     * @dev
     * Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(address redeemer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        // 1. Make sure redeemer is on last step
        uint256 _redeemerData = _balances[redeemer];
        _redemptionStep(_redeemerData, 3);
        // 2. Set all tokens in the redeemer's account to redeemed
        uint256 _tokenId;
        uint256 _tokenData;
        uint256 _batchSize = _getBatchSize(_redeemerData);
        uint256 _tokenOffsetMax;
        unchecked {
            _tokenOffsetMax = RPOS_TOKEN1 + (_batchSize*RUINT_SIZE);
        }
        for (uint256 _tokenOffset=RPOS_TOKEN1; _tokenOffset<_tokenOffsetMax;) {
            _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
            _tokenData = _owners[_tokenId];
            _setTokenValidity(_tokenId, _tokenData, REDEEMED);
            unchecked {
                _tokenOffset += RUINT_SIZE;
            }
        }
        _clearRedemptionData(redeemer);
    }

    // /**
    //  * @dev Temp function only used in the contract tests.
    //  */
    // function adminLock(uint256 tokenId)
    // external
    // onlyRole(DEFAULT_ADMIN_ROLE) {
    //     _owners[tokenId] = _lockToken(tokenId, _owners[tokenId]);
    // }

    /**
     * @dev Fail-safe function that can unlock an active token.
     * This is for any edge cases that may have been missed 
     * during redeemer testing. Dead tokens are still not 
     * possible to unlock, though they may be transferred to the 
     * contract owner where they may only be burned.
     */
    function adminUnlock(uint256 tokenId)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
        _unlockToken(tokenId);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
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
     * @dev Returns the list of redeemed tokens.
     */
    function getRedeemed()
    external view
    returns (uint24[] memory redeemedTokens) {
        redeemedTokens = _redeemedTokens;
    }

    /*
     * @dev Returns the minimum amount payable given batch size.
     * Shipping insurance as quoted Mar 2023 costs around ~1.2% 
     * of the value. We add a refundable buffer (~2%) for international 
     * shipments that will have a higher base.
     * Base package costs are around $20 CONUS. Thus the release 
     * fee can be summarized as $20 + (VALUE*2%).
     * Additional fees may be refunded.
     * Note: Max batch size can only be 6.
     */
    function getRedeemerFees(uint256 insuredValue, uint256 batchSize)
    public pure
    returns (uint256 total) {
        uint256 _insuredCost;
        uint256 _packagingBaseCost;
        unchecked {
            _insuredCost = 2*insuredValue/100;
            _packagingBaseCost = 20 + 2*batchSize;
            total = _packagingBaseCost + _insuredCost;
        }
    }

    /*
     * @dev Gets the redemption info/array of _tokenOwner.
     */
    function getRedeemerInfo(address account)
    external view
    returns(uint256 step, uint256[] memory tokenIds) {
        uint256 _balancesData = _balances[account];
        step = _getStep(_balancesData);
        tokenIds = _unpackTokenIds(_balancesData);
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * The IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup.
     */
    function isRedeemable(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _ownerData = _owners[tokenId];
        return _isRedeemable(tokenId, _ownerData);
    }

    /**
     * @dev
     * A view function to check if a token is already redeemed.
     */
    function isRedeemed(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _ownerData = _owners[tokenId];
        return _currentVId(_ownerData) == REDEEMED;
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function preRedeemable(uint256 tokenId)
    external view
    returns (bool) {
        uint256 _tokenData = _uTokenData[tokenId];
        return _preRedeemable(_tokenData);
    }

    /*
     * @dev Add individual tokens to an existing redemption process. 
     * Once user final fees have been paid, tokens can no longer 
     * be added to the existing batch.
     */
    function redeemAdd(address tokenOwner, uint256[] calldata tokenIds)
    external
    redeemerNotFrozen() {
        _callerApproved(tokenOwner);
        // 1. Check redeemer is already started
        uint256 _redeemerData = _balances[tokenOwner];
        _redemptionStep(_redeemerData, 2);
        // 2. Check existing batch already exists
        uint256 _oldBatchSize = _changeChecker(_redeemerData);
        // 3. Check new batch size fits within storage
        uint256 _addBatchSize = tokenIds.length;
        uint256 _newBatchSize = _addBatchSize+_oldBatchSize;
        if (_newBatchSize > MAX_BATCH_SIZE) {
            revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _newBatchSize);
        }
        // 4. Lock tokens
        _redeemLockTokens(tokenIds);
        // 5. Update batch size
        _redeemerData = _setTokenParam(
            _redeemerData,
            RPOS_BATCHSIZE,
            _newBatchSize,
            type(uint8).max
        );
        // 6. Update tokenIds in redeemer.
        uint256 _offset;
        unchecked {
            _offset = RPOS_TOKEN1 + RUINT_SIZE*_oldBatchSize;
        }
        for (uint256 i; i<_addBatchSize;) {
            _redeemerData = _setTokenParam(
                _redeemerData,
                _offset,
                tokenIds[i],
                type(uint24).max
            );
            unchecked {
                _offset += RUINT_SIZE;
                ++i;
            }
        }
        // 7. Save back to storage
        _balances[tokenOwner] = _redeemerData;
    }

    /**
     * @dev
     * Cancels redemption process from the token contract. It 
     * returns the redemption data that contains the list of 
     * tokenId to unlock.
     */
    function redeemCancel()
    external {
        uint256[] memory tokenIds = _unpackTokenIds(_balances[_msgSender()]);
        uint256 _batchSize = tokenIds.length;
        _checkBatchSize(_batchSize);
        for (uint256 i; i<_batchSize;) {
            _unlockToken(tokenIds[i]);
            unchecked {++i;}
        }
        _clearRedemptionData(_msgSender());
    }

    /**
     * @dev
     * Remove individual tokens from the redemption process.
     * This is useful is a tokenOwner wants to remove a 
     * fraction of tokens in the process. Otherwise it may 
     * end up being more expensive than cancel.
     */
    function redeemRemove(uint256[] calldata tokenIds)
    external {
        // 1. Check redeemer already started
        uint256 _redeemerData = _balances[_msgSender()];
        _redemptionStep(_redeemerData, 2);
        // 2. Check existing batch already exists
        uint256 _originalBatchSize = _changeChecker(_redeemerData);
        // 3. Check new batch size is valid
        uint256 _removedBatchSize = tokenIds.length;
        // 3a. Cancel is cheaper if removing the entire batch
        if (_removedBatchSize >= _originalBatchSize) {
            revert CancelRemainder(_removedBatchSize);
        }
        /*
        Swap and pop in memory instead of storage. This keeps 
        gas cost down.
        */
        uint256 _currentTokenId;
        uint256 _lastTokenId;
        uint256 _originalTokenId;
        uint256 _tokenOffset = RPOS_TOKEN1;
        uint256 _lastTokenOffset;
        uint256 _currentBatchSize = _originalBatchSize;
        for (uint256 i; i<_removedBatchSize;) { // Foreach token to remove
            _originalTokenId = tokenIds[i];
            // check caller is owner or approved
            _isApprovedOrOwner(_msgSender(), _ownerOf(_originalTokenId), _originalTokenId);
            for (uint256 j; j<_currentBatchSize;) { // check it against each existing token in the redeemer's batch
                _currentTokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                if (_currentTokenId == _originalTokenId) { // if a match is found
                    // get the last token in the batch
                    unchecked {
                        _lastTokenOffset = RPOS_TOKEN1+RUINT_SIZE*(_currentBatchSize-1);
                    }
                    _lastTokenId = uint256(uint24(_redeemerData>>_lastTokenOffset));
                    // and swap it to the current position of the token to remove
                    _redeemerData = _setTokenParam(
                        _redeemerData,
                        _tokenOffset,
                        _lastTokenId,
                        type(uint24).max
                    );
                    // subtract 1 from current batch size so the popped token (duplicate now) is no longer looked up
                    --_currentBatchSize;
                    // Unlock the removed token
                    _unlockToken(_originalTokenId);
                    break;
                }
                unchecked {
                    _tokenOffset += RUINT_SIZE;
                    ++j;
                }
            }
            _tokenOffset = RPOS_TOKEN1;
            unchecked {++i;}
        }

        // 4. Update remaining batchsize in packed _data
        _redeemerData = _setTokenParam(
            _redeemerData,
            RPOS_BATCHSIZE,
            _currentBatchSize,
            type(uint8).max
        );

        _balances[_msgSender()] = _redeemerData;
    }

    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     */
    function redeemStart(address tokenOwner, uint256[] calldata tokenIds)
    external
    redeemerNotFrozen() {
        _callerApproved(tokenOwner);
        // 1. Checks
        uint256 _redeemerData = _balances[tokenOwner];
        // 1b. Check account is registered
        if (!(_getRegistrationFor(_redeemerData) > 0)) {
            revert AddressMustFirstRegister(tokenOwner);
        }
        // 1c. Check account does not have open redemption
        _redemptionStep(_redeemerData, 0);
        // 1d. Check redemption batchsize is within limits
        uint256 _batchSize = tokenIds.length;
        if (_batchSize > MAX_BATCH_SIZE) {
            revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
        }
        // 2. Lock tokens
        _redeemLockTokens(tokenIds);
        // 3. Update redeemer data
        _redeemerData |= 2;
        _redeemerData |= _batchSize<<RPOS_BATCHSIZE;
        uint256 _offset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            _redeemerData |= tokenIds[i]<<_offset;
            unchecked {
                _offset += RUINT_SIZE;
                ++i;
            }
        }
        // 4. Save redeemer state
        _balances[tokenOwner] = _redeemerData;
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractPricer(address pricer)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    addressNotSame(contractPricer, pricer) {
        contractPricer = pricer;
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
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
     * @dev Sets the token validity. This method allows for 
     * a gasless digital signature redemption process where  
     * the admin can set the token to redeemed.
     */
    function setTokenValidity(uint256 tokenId, uint256 vId)
    external
    onlyRole(VALIDITY_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
        uint256 _tokenData = _owners[tokenId];
        uint256 _tokenValidity = _currentVId(_tokenData);
        if (vId == _tokenValidity) {
            revert ValueAlreadySet();
        }
        if (vId > REDEEMED) {
            if (_tokenValidity == VALID) {
                revert CannotValidToDead(tokenId, vId);
            }
        }
        _setTokenValidity(tokenId, _tokenData, vId);
    }

    /**
     * @dev Freezes or unfreezes redeemer portion of contract.
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
     * @dev Returns the number of redeemed tokens.
     */
    function totalRedeemed()
    external view
    returns (uint256) {
        return _redeemedTokens.length;
    }

    /**
     * @dev Step 2.
     * User verifies their info submitted to the frontend by checking 
     * email confirmation with code, then submitting confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 registrationCode)
    external payable
    redeemerNotFrozen() {
        // 1. Check redeemer has been started
        uint256 _redeemerData = _balances[_msgSender()];
        _redemptionStep(_redeemerData, 2);
        // 2. Check code
        if (registrationCode != _getRegistrationFor(_redeemerData)) {
            revert CodeMismatch();
        }
        // 3. Get latest on-chain insured value
        uint256[] memory tokenIds = _unpackTokenIds(_redeemerData);
        // 4. Get the estimated s&h fees
        uint256 _minRedeemUsd = getRedeemerFees(
            getInsuredsValue(tokenIds),
            tokenIds.length
        );            
        uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(
            _minRedeemUsd
        );
        // 4. Next step update
        _balances[_msgSender()] = _setTokenParam(
            _redeemerData,
            RPOS_STEP,
            3,
            type(uint8).max
        );
        // 5. Make sure payment amount is valid and successful
        if (msg.value != _minRedeemWei) {
            revert InvalidPaymentAmount(_minRedeemWei, msg.value);
        }
        (bool success,) = payable(owner).call{value: msg.value}("");
        if (!success) {
            revert PaymentFailure(_msgSender(), owner, msg.value);
        }
    }
}