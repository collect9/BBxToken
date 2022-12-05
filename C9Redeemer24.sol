// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Registrar2.sol";
import "./C9Struct.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {
    function add(address _tokenOwner, uint256[] calldata _tokenId) external;
    function cancel(address _tokenOwner) external returns(uint256 _data);
    function getMinRedeemUSD(uint256 _batchSize) external view returns(uint256);
    function getRedeemerInfo(address _tokenOwner) external view returns(uint256[] memory _info);
    function remove(address _tokenOwner, uint256[] calldata _tokenId) external;
    function start(address _tokenOwner, uint256[] calldata _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");

    uint256 constant POS_STEP = 0;
    uint256 constant POS_CODE = 8;
    uint256 constant POS_BATCHSIZE = 24;
    uint256 constant POS_TOKEN1 = 32;

    uint96 public redeemMinPrice = 20;
    address public contractPricer;
    uint256 private _seed;

    // Consider adding status in case admin final approval needs to disapprove
    // Status can represent some kind of error code
    mapping(address => uint256) redeemerData4; //code, step, batchsize, tokenId[]
    
    event RedeemerAdd(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256 indexed newBatchSize
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
        bool indexed registered,
        uint256 indexed batchSize
    );
    event RedeemerRemove(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256 indexed newBatchSize
    );
    event RedeemerUserFinalize(
        address indexed tokensOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        address indexed tokensOwner
    );

    address public contractRegistrar;
    address public immutable contractToken;
    
    constructor(uint256 seed_, address contractToken_) {
        contractToken = contractToken_;
        _seed = seed_;
        _grantRole(NFTCONTRACT_ROLE, contractToken_);
    }

    modifier redemptionStep(address _tokenOwner, uint256 _step) {
        uint256 _data = redeemerData4[_tokenOwner];
        if (_step != uint256(uint8(_data>>POS_STEP))) {
            _errMsg("wrong redemption step");
        }
        _;
    }

    function _checkBatchSize(uint256 _batchSize)
        internal pure {
            if (_batchSize == 0) {
                _errMsg("no batch in process");
            }
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Redeemer: ", message)));
    }

    function _removeRedemptionData(address _tokenOwner)
        internal {
            delete redeemerData4[_tokenOwner];
    }

    function _setTokenParam(
        uint256 _packedToken,
        uint256 _pos,
        uint256 _val,
        uint256 _mask
    )
        internal pure virtual
        returns(uint256) {
            _packedToken &= ~(_mask<<_pos); //zero out only its portion
            _packedToken |= _val<<_pos; //write value back in
            return _packedToken;
    }

    /*
     * @dev
     * Add individual tokens to an existing redemption process. 
     * Once user final fees have been paid, tokens can no longer 
     * be added to the existing batch.
     */
    function add(address _tokenOwner, uint256[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        notFrozen() {
            uint256 _data = redeemerData4[_tokenOwner];
            uint256 _batchSize = uint256(uint8(_data>>POS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            if (uint256(uint8(_data>>POS_STEP)) > 4) {
                _errMsg("current batch too far in process");
            }
            uint256 _addBatchSize = _tokenId.length;
            uint256 _newBatchSize = _addBatchSize+_batchSize;
            if (_newBatchSize > MAX_BATCH_SIZE) {
                _errMsg("max batch size is 9");
            }
            _data = _setTokenParam(_data, 24, _newBatchSize, 255);
            uint256 _offset = POS_TOKEN1 + UINT_SIZE*_batchSize;
            for (uint256 i; i<_addBatchSize;) {
                _data = _setTokenParam(
                    _data,
                    UINT_SIZE*i+_offset,
                    _tokenId[i],
                    4294967295
                );
                unchecked {++i;}
            }
            redeemerData4[_tokenOwner] = _data;
            emit RedeemerAdd(_tokenOwner, _batchSize, _newBatchSize);     
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
            uint256 _batchSize = uint256(uint8(_data>>POS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            uint256 _lastStep = uint256(uint8(_data>>POS_STEP));
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
            uint256 _originalBatchSize = uint256(uint8(_data>>POS_BATCHSIZE));
            _checkBatchSize(_originalBatchSize);
            uint256 _removedBatchSize = _tokenId.length;
            if (_removedBatchSize == _originalBatchSize) {
                _errMsg("cancel to remove remaining batch");
            }
            if (_removedBatchSize > _originalBatchSize) {
                _errMsg("some or all tokens not in batch");
            }
            /*
            Swap and pop in memory instead of storage. This keeps 
            gas cost down for larger _tokenId arrays.
            */
            uint256 _currentTokenId;
            uint256 _lastTokenId;
            uint256 _tokenOffset;
            uint256 _currentBatchSize = _originalBatchSize;
            for (uint256 i; i<_removedBatchSize;) { // foreach token to remove
                for (uint j; j<_currentBatchSize;) { // check it against each existing token
                    unchecked {_tokenOffset = POS_TOKEN1+UINT_SIZE*j;}
                    _currentTokenId = uint256(uint24(_data>>_tokenOffset));
                    if (_currentTokenId == _tokenId[i]) { // if a match is found
                        // get the last token
                        _lastTokenId = uint256(uint24(_data>>(POS_TOKEN1+UINT_SIZE*(_currentBatchSize-1))));
                        // and swap it to the current position (to remove it)
                        _data = _setTokenParam(
                            _data,
                            _tokenOffset,
                            _lastTokenId,
                            4294967295
                        );
                        // subtract 1 from current batch size
                        --_currentBatchSize;
                        break;
                    }
                    unchecked {++j;}
                }
                unchecked {++i;}
            }

            // Update new length in packed _data
            uint256 _newBatchSize = _originalBatchSize-_removedBatchSize;
            _data = _setTokenParam(_data, 24, _newBatchSize, 255);

            redeemerData4[_tokenOwner] = _data;
            emit RedeemerRemove(
                _tokenOwner,
                _originalBatchSize,
                _newBatchSize
            );  
    }

    /*
     * @dev
     * Returns the minimum amount payable given batch size.
     */
    function getMinRedeemUSD(uint256 _batchSize)
        public view override
        returns (uint256) {
            uint256 _n = _batchSize-1;
            uint256 _bps = _n == 0 ? 100 : 98**_n / 10**(_n*2-2);
            return redeemMinPrice*_batchSize*_bps/100;
    }

    /*
     * @dev
     * Gets the redemption info/array of _tokenOwner.
     */
    function getRedeemerInfo(address _tokenOwner)
        public view override
        returns(uint256[] memory _info) {
            uint256 _data = redeemerData4[_tokenOwner];
            uint256 _batchSize = uint256(uint8(_data>>POS_BATCHSIZE));
            _checkBatchSize(_batchSize);
            _info = new uint256[](_batchSize+3);
            _info[0] = uint256(uint8(_data>>POS_STEP));
            _info[1] = uint256(uint16(_data>>POS_CODE));
            _info[2] = _batchSize;
            for (uint256 i; i<_batchSize;) {
                _info[i+3] = uint256(uint24(_data>>(POS_TOKEN1+UINT_SIZE*i)));
                unchecked {++i;}
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
                _errMsg("max batch size is 9");
            }
            bool _registerOwner = IC9Registrar(contractRegistrar).isRegistered(_tokenOwner);
            uint256 _step = _registerOwner ? 4 : 2;
            uint256 _code;
            if (_step == 2) {
                unchecked {
                    _code = uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                block.difficulty,
                                block.number,
                                msg.sender,
                                _seed
                            )
                        )
                    ) % 65535;
                    _seed += _code;
                }
            }

            uint256 _newRedeemerData;
            _newRedeemerData |= _step<<0;
            _newRedeemerData |= _code<<8;
            _newRedeemerData |= _batchSize<<24;
            uint256 _offset;
            for (uint256 i; i<_batchSize;) {
                unchecked {_offset = UINT_SIZE*i+POS_TOKEN1;}
                _newRedeemerData |= _tokenId[i]<<_offset;
                unchecked {++i;}
            }
            redeemerData4[_tokenOwner] = _newRedeemerData;
            emit RedeemerInit(_tokenOwner, _registerOwner, _batchSize);     
    }

     /**
     * @dev Step 2a.
     * Admin retrieves code.
     */
    function adminGetRedemptionCode(address _tokenOwner)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256) {
            return uint256(uint16(redeemerData4[_tokenOwner]>>POS_CODE));
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
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenOwner, 2) {
            uint256 _data = redeemerData4[_tokenOwner];
            if (_code != uint256(uint16(_data>>POS_CODE))) {
                _errMsg("code mismatch");
            }
            _data = _setTokenParam(_data, 0, 3, 255);
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
            if (_code != uint256(uint16(_data>>POS_CODE))) {
                _errMsg("code mismatch");
            }
            _data = _setTokenParam(_data, 0, 4, 255);
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
    function userFinishRedemption()
        external payable
        redemptionStep(msg.sender, 4) {
            uint256 _data = redeemerData4[msg.sender];
            uint256 _batchSize = uint256(uint8(_data>>POS_BATCHSIZE));
            uint256 _minRedeemUsd = getMinRedeemUSD(_batchSize);
            // uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_minRedeemUsd);
            // if (msg.value < _minRedeemWei) {
            if (msg.value == 0) {
                _errMsg("invalid payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                _errMsg("payment failure");
            }
            _data = _setTokenParam(_data, 0, 5, 255);
            redeemerData4[msg.sender] = _data;
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
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenOwner, 5)
        notFrozen() {
            IC9Token(contractToken).redeemFinish(redeemerData4[_tokenOwner]);
            _removeRedemptionData(_tokenOwner);
            emit RedeemerAdminApprove(_tokenOwner, true);
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractPricer == _address) {
                _errMsg("contract already set");
            }
            contractPricer = _address;
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractRegistrar(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractRegistrar == _address) {
                _errMsg("contract already set");
            }
            contractRegistrar = _address;
    }

    /**
     * @dev Updates the minimum redemption price.
     */
    function setRedeemMinPrice(uint256 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (redeemMinPrice == _price) {
                _errMsg("price already set");
            }
            redeemMinPrice = uint96(_price);
    }
}