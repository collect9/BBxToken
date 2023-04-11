// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9Token6.sol";

import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Redeemable is C9Token {
    
    uint256 constant RPOS_BATCHSIZE = 0; // Pending number of redemptions
    uint256 constant RPOS_TOKEN1 = 8;
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

    /**
     * @dev Updates the addresse's redemptions count.
     */
    function _addRedemptionsTo(address from, uint256 batchSize)
    internal virtual {
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
        _balances[from] = balancesFrom;
    }

    /*
     * @dev Checks to see if the caller is approved for 
     * the redeemer.
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
        address _redeemer;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            // 1. Copy token data from storage
            _ownerData = _owners[_tokenId];
            // 2. Check caller is owner or approved
            _redeemer = address(uint160(_ownerData>>MPOS_OWNER));
            _isApprovedOrOwner(_msgSender(), _redeemer, _tokenId);
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
        uint256 _tokenData;
        for (uint256 i; i<_batchSize;) {
            _tokenId = _tokenIds[i];
            _tokenData = _owners[_tokenId];
            _setTokenValidity(_tokenId, _tokenData, REDEEMED);
            unchecked {++i;}
        }
        // 4. Clear redeemer's info so a new redemption can begin
        _clearRedemptionData(redeemer);
    }

    /**
     * @dev Fail-safe function that can unlock an active token.
     * This is for any edge cases that may have been missed 
     * during redeemer testing. Dead tokens are still not 
     * possible to unlock, though they may be transferred to the 
     * contract owner where they may only be burned.
     */
    function _adminUnlock(uint256 tokenId)
    private
    requireMinted(tokenId)
    notDead(tokenId) {
        _unlockToken(tokenId);
    }

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
     * Base package costs are around $25 CONUS. Thus the release 
     * fee can be summarized as $25 + 2%*VALUE.
     * Additional fees may be refunded.
     * Note: Max batch size 6.
     */
    function getRedemptionFees(uint256 insuredValue)
    public pure
    returns (uint256 total) {
        unchecked {
            total = 25 + 2*insuredValue/100;
        }
    }

    /*
     * @dev Gets the redemption info/array of redeemer.
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

    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     */
    function redeemStart(address redeemer, uint256 registrationCode, uint256[] calldata tokenIds)
    external payable
    redeemerNotFrozen() {
        _callerApproved(redeemer);
        // 1. Checks
        uint256 _redeemerData = _balances[redeemer];
        // 1b. Check account is registered
        if (!(_getRegistrationFor(_redeemerData) > 0)) {
            revert AddressMustFirstRegister(redeemer);
        }
        // 1c. Check account does not have a pending redemption
        uint256 _batchSize = _getBatchSize(_redeemerData);
        if (_batchSize > 0) {
            revert WrongProcessStep(0, 2);
        }
        // 1d. Check redemption batchsize is within limits
        _batchSize = tokenIds.length;
        if (_batchSize > MAX_BATCH_SIZE) {
            revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
        }
        // 2. Check registration code
        if (registrationCode != _getRegistrationFor(_redeemerData)) {
            revert CodeMismatch();
        }
        // 3. Lock tokens
        _redeemLockTokens(tokenIds);
        // 4. Get the estimated s&h fees
        uint256 _minRedeemUsd = getRedemptionFees(getInsuredsValue(tokenIds));            
        uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(
            _minRedeemUsd
        );
        // 5. Make sure payment amount is valid and successful
        if (msg.value != _minRedeemWei) {
            revert InvalidPaymentAmount(_minRedeemWei, msg.value);
        }
        (bool success,) = payable(owner).call{value: msg.value}("");
        if (!success) {
            revert PaymentFailure(_msgSender(), owner, msg.value);
        }
        // 6. Update redeemer data
        _redeemerData |= _batchSize<<RPOS_BATCHSIZE;
        uint256 _offset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            _redeemerData |= tokenIds[i]<<_offset;
            unchecked {
                _offset += RUINT_SIZE;
                ++i;
            }
        }
        // 7. Save redeemer state
        _balances[redeemer] = _redeemerData;
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
}