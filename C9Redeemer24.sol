// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./utils/C9Context.sol";
import "./C9OwnerControl.sol";

import "./interfaces/IC9Redeemer24.sol";
import "./interfaces/IC9Registrar.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Redeemer is C9Context, IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");

    mapping(address => uint256) redeemerData4; //batchsize, tokenIds[], step

    address private contractPricer;
    address public immutable contractToken;
    
    event RedeemerAdminApprove(
        address indexed tokensOwner,
        uint256[] tokenIds
    );

    constructor(address _contractToken) {
        contractToken = _contractToken;
        _grantRole(NFTCONTRACT_ROLE, _contractToken);
    }

    modifier redemptionStep(address _tokenOwner, uint256 _step) {
        uint256 _expected = redeemerData4[_tokenOwner]>>RPOS_STEP;
        if (_step != _expected) {
            revert WrongProcessStep(_expected, _step);
        }
        _;
    }

    function _checkBatchSize(uint256 _batchSize)
    private pure {
        if (_batchSize == 0) {
            revert AddressNotInProcess();
        }
    }

    /*
     * @dev Add individual tokens to an existing redemption process. 
     * Once user final fees have been paid, tokens can no longer 
     * be added to the existing batch.
     */
    function add(address _tokenOwner, uint256[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        notFrozen() {
            uint256 _data = redeemerData4[_tokenOwner];
            uint256 _batchSize = uint256(uint8(_data>>RPOS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            uint256 _currentStep = uint256(uint8(_data>>RPOS_STEP));
            if (_currentStep > 4) {
                revert AddressToFarInProcess(4, _currentStep);
            }
            uint256 _addBatchSize = _tokenId.length;
            uint256 _newBatchSize = _addBatchSize+_batchSize;
            if (_newBatchSize > MAX_BATCH_SIZE) {
                revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _newBatchSize);
            }
            _data = _setTokenParam(
                _data,
                RPOS_BATCHSIZE,
                _newBatchSize,
                type(uint8).max
            );
            uint256 _offset = RPOS_TOKEN1 + UINT_SIZE*_batchSize;
            for (uint256 i; i<_addBatchSize;) {
                _data = _setTokenParam(
                    _data,
                    _offset,
                    _tokenId[i],
                    type(uint24).max
                );
                unchecked {
                    _offset += UINT_SIZE;
                    ++i;
                }
            }
            redeemerData4[_tokenOwner] = _data;     
    }

    /**
     * @dev
     * Cancels redemption process from the token contract. It 
     * returns the redemption data that contains the list of 
     * tokenId to unlock.
     */
    function cancel(address _tokenOwner)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        returns(uint256 _data) {
            _data = redeemerData4[_tokenOwner];
            uint256 _batchSize = uint256(uint8(_data>>RPOS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            delete redeemerData4[_tokenOwner];
    }

    /*
     * @dev
     * Remove individual tokens from the redemption process.
     * This is useful is a tokenOwner wants to remove a 
     * fraction of tokens in the process. Otherwise it may 
     * end up being more expensive than cancel.
     */
    function remove(address _tokenOwner, uint256[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE) {
            uint256 _data = redeemerData4[_tokenOwner];
            uint256 _originalBatchSize = uint256(uint8(_data>>RPOS_BATCHSIZE));
            _checkBatchSize(_originalBatchSize);
            uint256 _removedBatchSize = _tokenId.length;
            if (_removedBatchSize == _originalBatchSize) {
                revert CancelRemainder(_removedBatchSize);
            }
            if (_removedBatchSize > _originalBatchSize) {
                revert SizeMismatch(_originalBatchSize, _removedBatchSize);
            }
            /*
            Swap and pop in memory instead of storage. This keeps 
            gas cost down for larger _tokenId arrays.
            */
            uint256 _currentTokenId;
            uint256 _lastTokenId;
            uint256 _tokenOffset = RPOS_TOKEN1;
            uint256 _currentBatchSize = _originalBatchSize;
            for (uint256 i; i<_removedBatchSize;) { // foreach token to remove
                for (uint256 j; j<_currentBatchSize;) { // check it against each existing token
                    _currentTokenId = uint256(uint24(_data>>_tokenOffset));
                    if (_currentTokenId == _tokenId[i]) { // if a match is found
                        // get the last token
                        _lastTokenId = uint256(uint24(_data>>(RPOS_TOKEN1+UINT_SIZE*(_currentBatchSize-1))));
                        // and swap it to the current position (to remove it)
                        _data = _setTokenParam(
                            _data,
                            _tokenOffset,
                            _lastTokenId,
                            type(uint24).max
                        );
                        // subtract 1 from current batch size
                        --_currentBatchSize;
                        break;
                    }
                    unchecked {
                        _tokenOffset += UINT_SIZE;
                        ++j;
                    }
                }
                _tokenOffset = RPOS_TOKEN1;
                unchecked {++i;}
            }

            // Update new length in packed _data
            uint256 _newBatchSize = _originalBatchSize-_removedBatchSize;
            _data = _setTokenParam(
                _data,
                RPOS_BATCHSIZE,
                _newBatchSize,
                type(uint8).max
            );

            redeemerData4[_tokenOwner] = _data;
    }

    /*
     * @dev Gets the redemption info/array of _tokenOwner.
     */
    function getRedeemerInfo(address _tokenOwner)
        public view override
        returns(uint256[] memory _info) {
            uint256 _data = redeemerData4[_tokenOwner];
            uint256 _batchSize = uint256(uint8(_data>>RPOS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            _info = new uint256[](_batchSize+2);
            _info[0] = _data>>RPOS_STEP;
            _info[1] = _batchSize;
            uint256 _offset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _info[i+2] = uint256(uint24(_data>>_offset));
                unchecked {
                    _offset += UINT_SIZE;
                    ++i;
                }
            }
    }

    /**
     * @dev Step 1.
     * Token owner initiates redemption process from token contract.
     * The step and code are pushed into the array first for convenience
     * as those are accessed more often throughout the process.
     */
    function start(address msgSender, uint256[] calldata tokenIds)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStep(msgSender, 0)
        notFrozen() {
            if (!IC9Token(contractToken).isRegistered(msgSender)) {
                revert AddressMustFirstRegister(msgSender);
            }
            uint256 _batchSize = tokenIds.length;
            if (_batchSize > MAX_BATCH_SIZE) {
                revert RedeemerBatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
            }
            
            uint256 _newRedeemerData = _batchSize;
            uint256 _offset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _newRedeemerData |= tokenIds[i]<<_offset;
                unchecked {
                    _offset += UINT_SIZE;
                    ++i;
                }
            }
            _newRedeemerData |= 2<<RPOS_STEP;

            // Save redeemer info to storage
            redeemerData4[msgSender] = _newRedeemerData;  
    }

    /**
     * @dev Step 2.
     * User verifies their info submitted to the frontend by checking 
     * email confirmation with code, then submitting confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 registrationCode)
    external
    redemptionStep(msg.sender, 2) {
        if (registrationCode != IC9Token(contractToken).getRegistrationFor(msg.sender)) {
            revert CodeMismatch();
        }
        redeemerData4[msg.sender] |= 3<<RPOS_STEP;
    }

    function _unpackTokenIds(uint256 redeemeerData)
    private pure
    returns (uint256[] memory tokenIds) {
        uint256 _batchSize = uint256(uint8(redeemeerData));
        tokenIds = new uint256[](_batchSize);
        uint256 _packedOffset = RPOS_TOKEN1;
        for (uint256 i; i<_batchSize;) {
            tokenIds[i] = uint256(uint24(redeemeerData>>_packedOffset));
            unchecked {
                _packedOffset += UINT_SIZE;
                ++i;
            }
        }
    }

    
    /*
     * @dev Returns the minimum amount payable given batch size.
     */
    function getRedeemerFees(uint256 insuredValue, uint256 batchSize)
    public pure
    returns (uint256 total) {
        uint256 _insuredCost = 5*insuredValue/100;
        uint256 _packagingBaseCost = 20 + 20*batchSize/4;
        total = _packagingBaseCost + _insuredCost;
    }

    /**
     * @dev Step 4.
     * User pays final fees that include insured shipping and 
     * handling costs. 
     * Note: Fee will need to be done externally, as periodically updating 
     * some kind of insured value within the C9Token could get extremely 
     * expensive even using packed data. A test of updating ~256 packed tokens
     * within a single call was estimated to cost ~1.5M gas.
     * Instead, a minimum amount is enforced to be payable. To 
     * prevent users purposely underpaying, an aminFinalApproval 
     * still follows this.
     */
    function userPayFinalFees()
        external payable
        redemptionStep(msg.sender, 3) {
            uint256 _redeemerData = redeemerData4[msg.sender];
            
            uint256[] memory tokenIds = _unpackTokenIds(_redeemerData);
            uint256 insuredValue = IC9Token(contractToken).getInsuredsValue(tokenIds);

            uint256 _minRedeemUsd = getRedeemerFees(insuredValue, tokenIds.length);            
            uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_minRedeemUsd);

            redeemerData4[msg.sender] |= 4<<RPOS_STEP;

            if (msg.value < _minRedeemWei) {
                revert InvalidPaymentAmount(_minRedeemWei, msg.value);
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                revert PaymentFailure(msg.sender, owner, msg.value);
            }
    }

    /**
     * @dev Step 5.
     * Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(address _tokenOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenOwner, 4)
        notFrozen() {
            uint256 _redeemerData = redeemerData4[msg.sender];
            uint256[] memory tokenIds = _unpackTokenIds(_redeemerData);
            IC9Token(contractToken).redeemFinish(redeemerData4[_tokenOwner]);
            delete redeemerData4[_tokenOwner];
            emit RedeemerAdminApprove(_tokenOwner, tokenIds);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(address pricer, address token) {
            pricer = contractPricer;
            token = contractToken;
    } 

    /**
     * @dev Updates the token contract address.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractPricer, _address) {
            contractPricer = _address;
    }
}