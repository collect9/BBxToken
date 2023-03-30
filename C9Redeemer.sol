// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9Token5.sol";

import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Redeemable is C9Token {
    
    bool private _frozenRedeemer;
    address private contractPricer;
    uint24[] private _redeemedTokens;

    uint256 constant RPOS_STEP = 0;
    uint256 constant RPOS_BATCHSIZE = 8; // Pending number of redemptions
    uint256 constant RPOS_TOKEN1 = 16;
    uint256 constant MAX_BATCH_SIZE = 6;
    uint256 constant RUINT_SIZE = 24;

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
     * @dev Checks to make sure user is on correct redemption step.
     */ 
    modifier redemptionStep(uint256 step) {
        uint256 _expected = _getStep(_balances[_msgSender()]);
        if (step != _expected) {
            revert WrongProcessStep(_expected, step);
        }
        _;
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
        _balances[redeemer] = _setTokenParam(
            _balances[redeemer], 0, 0,
            type(uint160).max
        );
    }

    function _getBatchSize(uint256 balancesData)
    private pure
    returns (uint256) {
        return uint256(uint8(balancesData>>RPOS_BATCHSIZE));
    }

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
        uint256 _tokenData;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            // 1. Check token exists (implicit via ownerOf()) and that caller is owner or approved
            _isApprovedOrOwner(_msgSender(), ownerOf(_tokenId), _tokenId);
            // 2. Copy token data from storage
            _tokenData = _owners[_tokenId];
            // 3. Check token is redeemable
            if (!_isRedeemable(_tokenId, _tokenData)) {
                revert TokenNotRedeemable(_tokenId);
            }
            /* 4. If redeemable but locked, token is already in redeemer.
                  This will also prevent multiple approved trying to
                  redeem the same token at once.
            */
            if (_isLocked(_tokenData)) {
                revert TokenIsLocked(_tokenId);
            }
            // 5. All checks pass, so lock the token
            _tokenData = _lockToken(_tokenId, _tokenData);
            // 6. Save to storage
            _owners[_tokenId] = _tokenData;
            unchecked {++i;}
        }
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
        // 1. Set all tokens in the redeemer's account to redeemed
        uint256 _tokenId;
        uint256 _redeemerData = _balances[redeemer];
        uint256 _batchSize = _getBatchSize(_redeemerData);
        uint256 _tokenOffsetMax;
        unchecked {
            _tokenOffsetMax = RPOS_TOKEN1 + (_batchSize*RUINT_SIZE);
        }
        for (uint256 _tokenOffset=RPOS_TOKEN1; _tokenOffset<_tokenOffsetMax;) {
            _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
            _setTokenValidity(_tokenId, REDEEMED);
            _redeemedTokens.push(uint24(_tokenId));
            unchecked {
                _tokenOffset += RUINT_SIZE;
            }
        }
        // 2. Update the token redeemer's redemption count
        _addRedemptionsTo(redeemer, _batchSize);
        _clearRedemptionData(redeemer);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
    external view override
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
        uint256 _insuredCost = 2*insuredValue/100;
        uint256 _packagingBaseCost = 20 + 2*batchSize;
        total = _packagingBaseCost + _insuredCost;
    }

    /*
     * @dev Gets the redemption info/array of _tokenOwner.
     */
    function getRedeemerInfo(address account)
    public view
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
    requireMinted(tokenId)
    returns (bool) {
        return _isRedeemable(tokenId, _owners[tokenId]);
    }

    /**
     * @dev
     * A view function to check if a token is already redeemed.
     */
    function isRedeemed(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        return _currentVId(_owners[tokenId]) == REDEEMED;
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function preRedeemable(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        return _preRedeemable(_uTokenData[tokenId]);
    }

    /*
     * @dev Add individual tokens to an existing redemption process. 
     * Once user final fees have been paid, tokens can no longer 
     * be added to the existing batch.
     */
    function redeemAdd(uint256[] calldata tokenIds)
    external
    redeemerNotFrozen() {
        // 1. Check existing batch already exists
        uint256 _redeemerData = _balances[_msgSender()];
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
        uint256 _offset = RPOS_TOKEN1 + RUINT_SIZE*_oldBatchSize;
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
        _balances[_msgSender()] = _redeemerData;
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
        // 1. Check existing batch already exists
        uint256 _redeemerData = _balances[_msgSender()];
        uint256 _originalBatchSize = _changeChecker(_redeemerData);
        // 2. Check new batch size is valid
        uint256 _removedBatchSize = tokenIds.length;
        // 2a. Cancel is cheaper if removing the entire batch
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
        uint256 _currentBatchSize = _originalBatchSize;
        for (uint256 i; i<_removedBatchSize;) { // foreach token to remove
            _originalTokenId = tokenIds[i];
            for (uint256 j; j<_currentBatchSize;) { // check it against each existing token in the redeemer's batch
                _currentTokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                if (_currentTokenId == _originalTokenId) { // if a match is found
                    // get the last token in the batch
                    _lastTokenId = uint256(uint24(_redeemerData>>(RPOS_TOKEN1+RUINT_SIZE*(_currentBatchSize-1))));
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

        // Update remaining batchsize in packed _data
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
    function redeemStart(uint256[] calldata tokenIds)
    external
    redeemerNotFrozen() {
        // 1. Checks
        uint256 _redeemerData = _balances[_msgSender()];
        // 1b. Check account is registered
        if (!(_getRegistrationFor(_redeemerData) > 0)) {
            revert AddressMustFirstRegister(_msgSender());
        }
        // 1c. Check account does not have open redemption
        uint256 _step = _getStep(_redeemerData);
        if (_step != 0) {
            revert WrongProcessStep(0, _step);
        }
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
        _balances[_msgSender()] = _redeemerData;
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
    redemptionStep(2)
    redeemerNotFrozen() {
        // 1. Checks
        uint256 _redeemerData = _balances[_msgSender()];
        if (registrationCode != _getRegistrationFor(_redeemerData)) {
            revert CodeMismatch();
        }
        // 2. Get latest on-chain insured value
        uint256[] memory tokenIds = _unpackTokenIds(_redeemerData);
        // 3. Get the estimated s&h fees
        uint256 _minRedeemUsd = getRedeemerFees(
            getInsuredsValue(tokenIds),
            tokenIds.length
        );            
        // uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(
        //     _minRedeemUsd
        // );
        uint256 _minRedeemWei = 0;
        // 4. Next step update
        _balances[_msgSender()] = _setTokenParam(
            _balances[_msgSender()],
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