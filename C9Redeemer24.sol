// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./C9Registrar.sol";
import "./C9Token.sol";
import "./utils/EthPricer.sol";

uint256 constant RPOS_STEP = 0;
uint256 constant RPOS_CODE = 8;
uint256 constant RPOS_BATCHSIZE = 24;
uint256 constant RPOS_TOKEN1 = 32;
uint256 constant UINT_SIZE = 24;
uint256 constant MAX_BATCH_SIZE = 9;

error AddressToFarInProcess(uint256 minStep, uint256 received); //0xb078ecc8
error CancelRemainder(uint256 remainingBatch); //0x2c9f7f1d
error SizeMismatch(uint256 maxSize, uint256 received); //0x97ce59d2

interface IC9Redeemer {
    function add(address _tokenOwner, uint256[] calldata _tokenId) external;
    function cancel(address _tokenOwner) external returns(uint256 _data);
    function getMinRedeemUSD(uint256 _batchSize) external view returns(uint256);
    function getRedeemerInfo(address _tokenOwner) external view returns(uint256[] memory _info);
    function remove(address _tokenOwner, uint256[] calldata _tokenId) external;
    function start(address _tokenOwner, uint256[] calldata _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant FRONTEND_ROLE = keccak256("FRONTEND_ROLE");
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    uint96 public redeemMinPrice = 20;
    address private contractPricer;
    address private contractRegistrar;
    address private immutable contractToken;

    mapping(address => uint256) redeemerData4; //step, code, batchsize, tokenId[]
    
    event RedeemerAdd(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256[] indexed tokenId
    );
    event RedeemerAdminApprove(
        address indexed tokensOwner,
        bool indexed complete
    );
    event RedeemerCancel(
        address indexed tokensOwner,
        uint256 indexed processStep,
        uint256 indexed batchSize
    );
    event RedeemerInit(
        address indexed tokensOwner,
        uint256 indexed nextStep,
        uint256[] indexed tokenId
    );
    event RedeemerRemove(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256[] indexed tokenId
    );
    event RedeemerUserFinalize(
        address indexed tokensOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        address indexed tokensOwner
    );

    constructor(address contractToken_) {
        contractToken = contractToken_;
        _grantRole(FRONTEND_ROLE, msg.sender); // remove after testing actual frontend
        _grantRole(NFTCONTRACT_ROLE, contractToken_);
    }

    /*
     * @dev Checks if address is the same before update. There are 
     * a few functions that update addresses where this is used.
     */ 
    modifier addressNotSame(address _old, address _new) {
        if (_old == _new) {
            revert AddressAlreadySet();
        }
        _;
    }

    modifier redemptionStep(address _tokenOwner, uint256 _step) {
        uint256 _data = redeemerData4[_tokenOwner];
        uint256 _expectedStep = uint256(uint8(_data>>RPOS_STEP));
        if (_step != _expectedStep) {
            revert WrongProcessStep(_expectedStep, _step);
        }
        _;
    }

    function _checkBatchSize(uint256 _batchSize)
        private pure {
            if (_batchSize == 0) {
                revert AddressNotInProcess();
            }
    }

    function _removeRedemptionData(address _tokenOwner)
        private {
            delete redeemerData4[_tokenOwner];
    }

    function _setTokenParam(
        uint256 _packedToken,
        uint256 _pos,
        uint256 _val,
        uint256 _mask
    )
        private pure
        returns(uint256) {
            _packedToken &= ~(_mask<<_pos); //zero out only its portion
            _packedToken |= _val<<_pos; //write value back in
            return _packedToken;
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
                revert BatchSizeTooLarge(MAX_BATCH_SIZE, _newBatchSize);
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
            emit RedeemerAdd(_tokenOwner, _batchSize, _tokenId);     
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
            uint256 _lastStep = uint256(uint8(_data>>RPOS_STEP));
            _removeRedemptionData(_tokenOwner);
            emit RedeemerCancel(_tokenOwner, _lastStep, _batchSize);
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
            emit RedeemerRemove(
                _tokenOwner,
                _originalBatchSize,
                _tokenId
            );  
    }

    /*
     * @dev Returns the minimum amount payable given batch size.
     */
    function getMinRedeemUSD(uint256 _batchSize)
        public view override
        returns (uint256) {
            if (_batchSize == 0) {
                revert ZeroValue();
            }
            if (_batchSize > MAX_BATCH_SIZE) {
                revert BatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
            }
            uint256 _n = _batchSize-1;
            uint256 _bps = _n == 0 ? 100 : 98**_n / 10**(_n*2-2);
            return redeemMinPrice*_batchSize*_bps/100;
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
            _info = new uint256[](_batchSize+3);
            _info[0] = uint256(uint8(_data>>RPOS_STEP));
            _info[1] = uint256(uint16(_data>>RPOS_CODE));
            _info[2] = _batchSize;
            uint256 _offset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _info[i+3] = uint256(uint24(_data>>_offset));
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
    function start(address _tokenOwner, uint256[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStep(_tokenOwner, 0)
        notFrozen() {
            uint256 _batchSize = _tokenId.length;
            if (_batchSize > MAX_BATCH_SIZE) {
                revert BatchSizeTooLarge(MAX_BATCH_SIZE, _batchSize);
            }
            uint256 _step = IC9Registrar(contractRegistrar).isRegistered(_tokenOwner) ? 4 : 2;
            uint256 _code;
            if (_step == 2) {
                unchecked {
                    _code = uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                block.difficulty,
                                block.number,
                                msg.sender
                            )
                        )
                    ) % 65535;
                }
            }

            uint256 _newRedeemerData;
            _newRedeemerData |= _step<<RPOS_STEP;
            _newRedeemerData |= _code<<RPOS_CODE;
            _newRedeemerData |= _batchSize<<RPOS_BATCHSIZE;
            uint256 _offset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _newRedeemerData |= _tokenId[i]<<_offset;
                unchecked {
                    _offset += UINT_SIZE;
                    ++i;
                }
            }
            redeemerData4[_tokenOwner] = _newRedeemerData;
            emit RedeemerInit(_tokenOwner, _step, _tokenId);     
    }

     /**
     * @dev Step 2a.
     * Admin retrieves code.
     */
    function adminGetRedemptionCode(address _tokenOwner)
        external view
        onlyRole(FRONTEND_ROLE)
        returns (uint256) {
            return uint256(uint16(redeemerData4[_tokenOwner]>>RPOS_CODE));
    }

    /**
     * @dev Step 2b.
     * Admin confirms user info via front end was received. Code  
     * is emailed to that specified within info, along with the 
     * rest of the info for the user to verify info is correct.
     * Cost: ~38,000 gas
     */
    function adminVerifyRedemptionCode(address _tokenOwner, uint256 _code)
        external
        onlyRole(FRONTEND_ROLE)
        redemptionStep(_tokenOwner, 2) {
            uint256 _data = redeemerData4[_tokenOwner];
            if (_code != uint256(uint16(_data>>RPOS_CODE))) {
                revert CodeMismatch();
            }
            _data = _setTokenParam(
                _data,
                RPOS_STEP,
                3,
                type(uint8).max
            );
            redeemerData4[_tokenOwner] = _data;
            emit RedeemerAdminApprove(_tokenOwner, false);
    }

    /**
     * @dev Step 3.
     * User verifies their info submitted to the frontend by checking 
     * email confirmation with code, then submitting confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 _code)
        external
        redemptionStep(msg.sender, 3) {
            uint256 _data = redeemerData4[msg.sender];
            if (_code != uint256(uint16(_data>>RPOS_CODE))) {
                revert CodeMismatch();
            }
            _data = _setTokenParam(
                _data,
                RPOS_STEP,
                4,
                type(uint8).max
            );
            redeemerData4[msg.sender] = _data;
            emit RedeemerUserVerify(msg.sender);
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
        redemptionStep(msg.sender, 4) {
            uint256 _data = redeemerData4[msg.sender];
            uint256 _batchSize = uint256(uint8(_data>>RPOS_BATCHSIZE));
            uint256 _minRedeemUsd = getMinRedeemUSD(_batchSize);
            uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_minRedeemUsd);
            _data = _setTokenParam(
                _data,
                RPOS_STEP,
                5,
                type(uint8).max
            );
            redeemerData4[msg.sender] = _data;
            if (msg.value < _minRedeemWei) {
                revert InvalidPaymentAmount(_minRedeemWei, msg.value);
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                revert PaymentFailure();
            }
            emit RedeemerUserFinalize(msg.sender, msg.value);
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
        onlyRole(FRONTEND_ROLE)
        redemptionStep(_tokenOwner, 5)
        notFrozen() {
            IC9Token(contractToken).redeemFinish(redeemerData4[_tokenOwner]);
            _removeRedemptionData(_tokenOwner);
            emit RedeemerAdminApprove(_tokenOwner, true);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(address pricer, address registrar, address token) {
            pricer = contractPricer;
            registrar = contractRegistrar;
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

    /**
     * @dev Updates the token contract address.
     */
    function setContractRegistrar(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractRegistrar, _address) {
            contractRegistrar = _address;
    }

    /**
     * @dev Updates the minimum redemption price.
     */
    function setRedeemMinPrice(uint256 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (redeemMinPrice == _price) {
                revert ValueAlreadySet();
            }
            redeemMinPrice = uint96(_price);
    }
}