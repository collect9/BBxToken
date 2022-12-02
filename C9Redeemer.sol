// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Registrar.sol";
import "./C9Struct.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {
    function add(address _tokensOwner, uint32[] calldata _tokenId) external;
    function cancel(address _tokensOwner) external returns(uint32[] memory _data, uint256 _batchSize);
    function getRedemptionStep(address _tokenOwner) external view returns(uint256);
    function getRedemptionInfo(address _tokensOwner) external view returns(uint32[] memory);
    function start(address _tokensOwner, uint32[] calldata _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    uint96 public redeemMinPrice = 20;
    address public contractPricer;

    mapping(address => uint32[]) redeemerData; //tokenId[], code, step
    
    event RedeemerAdd(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256 indexed newBatchSize
    );
    event RedeemerAdminApprove(
        address indexed tokenOwner
    );
    event RedeemerAdminFinalApproval(
        address indexed tokenOwner
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
    event RedeemerUserFinalize(
        address indexed tokenOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        address indexed tokenOwner
    );

    address public contractRegistrar;
    address public immutable contractToken;
    
    constructor(address _contractToken) {
        contractToken = _contractToken;
        _grantRole(NFTCONTRACT_ROLE, _contractToken);
    }

    modifier redemptionStep(address _tokenOwner, uint256 _step) {
        if (_step != getRedemptionStep(_tokenOwner)) {
            _errMsg("wrong redemption step");
        }
        _;
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Redeemer: ", message)));
    }

    /**
     * @dev
     */
    function _genCode() 
        internal view
        returns(uint256) {
            return uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        block.number,
                        msg.sender
                    )
                )
            ) % 10**6;
    }

    function _paymentHandler(uint256 _minRedeemWei)
        internal {
            if (msg.value < _minRedeemWei) {
                _errMsg("invalid payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                _errMsg("payment failure");
            }
    }

    function _removeRedemptionData(address _tokensOwner)
        internal {
            delete redeemerData[_tokensOwner];
    }

    /**
     * @dev (batch version)
     * This needs to return the tokenId array to know which tokens to
     * unlock in the main contract.
     * Cost:
     * 1x token = 48,900 gas    -> 48,900 gas per
     * 2x token = 60,600 gas    -> 30,300 gas per
     * 6x token = 108,000 gas   -> 18,000 gas per
     * 10x token = 155,000 gas  -> 15,500 gas per
     * 14x token = 203,000 gas  -> 14,500 gas per
     */
    function cancel(address _tokensOwner)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        returns(uint32[] memory _data, uint256 _batchSize) {
            _data = redeemerData[_tokensOwner];
            if (_data.length == 0) {
                _errMsg("no batch in process");
            }
            _batchSize = _data.length-2;
            _removeRedemptionData(_tokensOwner);
            emit RedeemerCancel(_tokensOwner, _data[0], _data.length-2);
    }

    /*
     * @dev Gets the redemption (batch) _tokenOwner is at.
     */
    function getRedemptionInfo(address _tokensOwner)
        public view override
        returns(uint32[] memory) {
            return redeemerData[_tokensOwner];
    }

    /*
     * @dev Gets the redemption (batch) _tokenOwner is at.
     */
    function getRedemptionStep(address _tokensOwner)
        public view override
        returns(uint256) {
            uint32[] memory _data = getRedemptionInfo(_tokensOwner);
            return _data.length > 0 ? _data[0] : 0;
    }

    /**
     * @dev Step 1. (batch version)
     * Cost: mentioned in C9Token redeemStart()
     * 1x token = 108,000 gas   -> 108,000 gas per
     * 2x token = 123,000 gas   -> 61,500 gas per
     * 6x token = 185,000 gas   -> 31,800 gas per
     * 10x token = 269,000 gas  -> 26,900 gas per
     * 14x token = 332,000 gas  -> 23,700 gas per
    */
    function start(address _tokensOwner, uint32[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStep(_tokensOwner, 0)
        notFrozen() {
            if (_tokenId.length > MAX_BATCH_SIZE) {
                _errMsg("max batch size is 22");
            }
            bool _registerOwner = IC9Registrar(contractRegistrar).addressRegistered(_tokensOwner);
            uint256 step = _registerOwner ? 4 : 2;
            redeemerData[_tokensOwner].push(uint32(step));
            redeemerData[_tokensOwner].push(uint32(_genCode()));
            for (uint256 i; i<_tokenId.length; i++) {
                redeemerData[_tokensOwner].push(_tokenId[i]);
            }
            emit RedeemerInit(_tokensOwner, _registerOwner, _tokenId.length);     
    }

    function add(address _tokensOwner, uint32[] calldata _tokenId)
        external override
        //onlyRole(NFTCONTRACT_ROLE)
        notFrozen() {
            uint32[] memory _data = redeemerData[_tokensOwner];
            if (_data.length == 0) {
                _errMsg("no batch in process");
            }
            if (_data[0] > 3) {
                _errMsg("current batch too far in process");
            }
            uint256 _existingPending = _data.length-2;
            uint256 _newBatchSize = _tokenId.length+_existingPending;
            if (_newBatchSize > MAX_BATCH_SIZE) {
                _errMsg("max batch size is 22");
            }
            for (uint256 i; i<_tokenId.length; i++) {
                redeemerData[_tokensOwner].push(_tokenId[i]);
            }
            emit RedeemerAdd(_tokensOwner, _existingPending, _newBatchSize);     
    }

    /*

    */
    function remove(address _tokensOwner, uint32[] calldata _tokenId)
        external //overide
        //onlyRole(NFTCONTRACT_ROLE)
        {
        uint32[] memory _data = redeemerData[_tokensOwner];
        if (_data.length == 0) {
            _errMsg("no batch in process");
        }
        uint256 _existingPending = _data.length-2;
        if (_tokenId.length == _existingPending) {
            _errMsg("use cancel to remove whole batch");
        }
        if (_tokenId.length > _existingPending) {
            _errMsg("cannot remove more than in batch");
        }
        
        for (uint256 i; i<_tokenId.length; i++) {
            for (uint j; j<_data.length; j++) {
                if (_tokenId[i] == _data[j+2]) {
                    // Swap, copy to storage, pop, copy back to memory
                    _data[j+2] = _data[_data.length-1];
                    redeemerData[_tokensOwner] = _data;
                    redeemerData[_tokensOwner].pop();
                    _data = redeemerData[_tokensOwner];
                    break;
                }
            }
        }
    }

    function adminGetRedemptionCode(address _tokensOwner)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256) {
            return redeemerData[_tokensOwner][1];
    }

    /**
     * @dev Step 2b. (batch version)
     * Admin confirms user info via front end was received. Code  
     * is emailed to that specified within info, along with the 
     * rest of the info for the user to verify.
     * Cost: ~38,000 gas
     */
    function adminVerifyRedemptionCode(address _tokensOwner, uint256 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokensOwner, 2) {
            if (_code != redeemerData[_tokensOwner][1]) {
                _errMsg("code mismatch");
            }
            redeemerData[_tokensOwner][0] = 3;
            emit RedeemerAdminApprove(_tokensOwner);
    }

    /**
     * @dev Step 3. (batch version)
     * User verifies their info submitted to the frontend by checking 
     * email confirmation with code, then submitting confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 _code)
        external
        redemptionStep(msg.sender, 3) {
            if (_code !=redeemerData[msg.sender][1]) {
                _errMsg("code mismatch");
            }
            redeemerData[msg.sender][0] = 4;
            emit RedeemerUserVerify(msg.sender);
    }

    /**
     * @dev Step 4. (batch version)
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
            // uint256 _batchSize = _redemptionData[msg.sender].tokenId.length;
            // uint256 _n = _batchSize-1;
            // uint256 _bps = _n == 0 ? 100 : 98**_n / 10**(_n*2-2);
            // uint256 _minRedeemUsd = redeemMinPrice*_batchSize*_bps/100;
            // uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_minRedeemUsd);
            // _paymentHandler(_minRedeemWei);
            redeemerData[msg.sender][0] = 5;
            emit RedeemerUserFinalize(msg.sender, msg.value);
    }

    /**
     * @dev Step 5. (BATCH)
     * Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(address _tokensOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokensOwner, 5)
        notFrozen() {
            IC9Token(contractToken).redeemFinish(redeemerData[_tokensOwner]);
            _removeRedemptionData(_tokensOwner);
            emit RedeemerAdminFinalApproval(_tokensOwner);
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