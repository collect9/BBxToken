// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Registrar.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {    
    function cancel(uint256 _tokenId) external;
    function cancelBatch(address _tokensOwner) external returns(uint32[22] memory _tokenId);
    function getRedemptionStep(uint256 _tokenId) external view returns (uint256);
    function getBatchRedemptionStep() external view returns(uint256);
    function start(uint256 _tokenId) external;
    function startBatch(address _tokensOwner, uint256[] calldata _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32[2]) _redemptionData; //code, step
    mapping(address => uint32[]) _batchRedemptionData; //code, step, token1, token2..., tokenN

    event RedeemerAdminApprove(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RedeemerAdminApproveBatch(
        address indexed tokenOwner
    );
    event RedeemerCancel(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint256 indexed processStep
    );
    event RedeemerBatchCancel(
        address indexed tokensOwner,
        uint256 indexed batchSize,
        uint32 indexed processStep
    );
    event RedeemerGenCode(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RedeemerInit(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        bool indexed registered
    );
    event RedeemerBatchInit(
        address indexed tokensOwner,
        uint256 batchSize,
        bool indexed registered
    );
    event RedeemerUserFinalize(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint256 indexed fees
    );
    event RedeemerUserFinalizeBatch(
        address indexed tokenOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RedeemerUserVerifyBatch(
        address indexed tokenOwner
    );

    uint96 private _incrementer = uint96(block.number);
    address public contractRegistrar;
    address public immutable contractToken;
    
    constructor(address _contractToken) {
        contractToken = _contractToken;
        _grantRole(NFTCONTRACT_ROLE, _contractToken);
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            _errMsg("unauthorized");
        }
        _;
    }

    modifier redemptionStep(uint256 _tokenId, uint256 _step) {
        if (_step != _redemptionData[_tokenId][1]) {
            _errMsg("wrong redemption step");
        }
        _;
    }

    modifier redemptionStepBatch(address _tokenOwner, uint256 _step) {
        uint32[] memory _batchData = _batchRedemptionData[_tokenOwner];
        if (_step == 0) {
            if (_batchData.length > 0) {
                _errMsg("wrong batch redemption step");
            }
        }
        else {
            if (_step != _batchData[1]) {
                _errMsg("wrong batch redemption step");
            }
        }
        _;
    }

    modifier tokenLocked(uint256 _tokenId) {
        if (!IC9Token(contractToken).tokenLocked(_tokenId)) {
            _errMsg("token not locked");
        }
        _;
    }

    modifier tokenLockedBatch(uint256[] calldata _tokenId) {
        uint256 _batchSize = _tokenId.length;
        for(uint i; i<_batchSize; i++) {
            if (!IC9Token(contractToken).tokenLocked(_tokenId[i])) {
                _errMsg("batch token not locked");
            }
        }
        _;
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Redeemer: ", message)));
    }

    /**
     * @dev Removes any redemption info after redemption is finished 
     * or if token own calls this contract (from the token contract) 
     * having caneled redemption.
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
                        msg.sender,
                        _incrementer
                    )
                )
            ) % 10**6;
    }

    /**
     * @dev Removes any redemption info after redemption is finished 
     * or if token own calls this contract (from the token contract) 
     * having caneled redemption.
     */
    function _removeRedemptionData(uint256 _tokenId)
        internal {
            delete _redemptionData[_tokenId];
    }

    function _removeBatchRedemptionData(address _tokensOwner)
        internal {
            delete _batchRedemptionData[_tokensOwner];
    }

    function getRedemptionStep(uint256 _tokenId)
        external view override
        returns(uint256) {
            return uint256(_redemptionData[_tokenId][1]);
    }

    function getBatchRedemptionStep()
        external view override
        returns(uint256) {
            uint32[] memory _data = _batchRedemptionData[msg.sender];
            if (_data.length == 0) {
                return 0;
            }
            else {
                return _data[1];
            }
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     */
    function cancel(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE) {
            if (_redemptionData[_tokenId][1] == 0) {
                _errMsg("token not in process");
            }
            _removeRedemptionData(_tokenId);
            emit RedeemerCancel(_tokenId, msg.sender, _redemptionData[_tokenId][1]);
    }

    function cancelBatch(address _tokensOwner)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        returns(uint32[22] memory _tokenId) {
            uint32[] memory _data = _batchRedemptionData[_tokensOwner];
            if (_data.length == 0) {
                _errMsg("batch tokens not in process");
            }
            for (uint i=2; i<_data.length; i++) {
                _tokenId[i-2] = _data[i];
            }
            _removeBatchRedemptionData(_tokensOwner);
            emit RedeemerBatchCancel(_tokensOwner, _data.length, _data[1]);
    }

    /**
     * @dev Step 1.
     * User initializes redemption.
     */
    function start(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLocked(_tokenId)
        redemptionStep(_tokenId, 0)
        notFrozen() {
            // Check to see if owner is already registered
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            bool _registerOwner = IC9Registrar(contractRegistrar).addressRegistered(_tokenOwner);
            _incrementer += 1;
            if (_registerOwner) {
                // If registered jump to step 4
                _redemptionData[_tokenId][1] = 4;
                emit RedeemerInit(_tokenId, msg.sender, true);
            }
            else {
                // Else move to next step
                _redemptionData[_tokenId][0] = uint32(_genCode());
                _redemptionData[_tokenId][1] = 2;
                emit RedeemerInit(_tokenId, msg.sender, false);
            }
    }

    /**
     * @dev Step 1 (BATCH).
     */
    function startBatch(address _tokensOwner, uint256[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLockedBatch(_tokenId)
        redemptionStepBatch(_tokensOwner, 0)
        notFrozen() {
            uint256 batchSize = _tokenId.length;
            if (batchSize > 22) {
                _errMsg("max batch size is 22");
            }
            bool _registerOwner = IC9Registrar(contractRegistrar).addressRegistered(_tokensOwner);
            _incrementer += uint96(batchSize);
            if (_registerOwner) {
                // If registered jump to step 4
                _batchRedemptionData[_tokensOwner].push(0); // dummy code
                _batchRedemptionData[_tokensOwner].push(4);
                emit RedeemerBatchInit(msg.sender, batchSize, true);
            }
            else {
                // Else move to next step
                _batchRedemptionData[_tokensOwner].push(uint32(_genCode()));
                _batchRedemptionData[_tokensOwner].push(2);
                emit RedeemerBatchInit(msg.sender, batchSize, false);
            }

            // Check to make sure all tokenId are of the same owner - make batch ownerOf?
            for (uint256 i; i<batchSize; i++) {
                if (C9Token(contractToken).ownerOf(_tokenId[i]) != _tokensOwner) {
                    _errMsg("unauthorized");
                }
                _batchRedemptionData[_tokensOwner].push(uint32(_tokenId[i]));
            }
    }

    /**
     * @dev Step 2a.
     * Admin/backend retrieves info.
     */
    function adminGetRedemptionCode(uint256 _tokenId)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint32) {
            return _redemptionData[_tokenId][0];
    }

    /**
     * @dev Step 2a. (BATCH)
     */
    function adminGetRedemptionCodeBatch(address _tokensOwner)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint32) {
            return _batchRedemptionData[_tokensOwner][0];
    }

    /**
     * @dev Step 2b.
     * Admin confirms receipt of info by sending code 
     * to email specified in info, along with the rest of the info 
     * for the user to verify.
     * Cost: ~38,000 gas
     */
    function adminVerifyRedemptionCode(uint256 _tokenId, uint256 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenId, 2) {
            if (_code != _redemptionData[_tokenId][0]) {
                _errMsg("code mismatch");
            }
            _redemptionData[_tokenId][1] = 3;
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            emit RedeemerAdminApprove(_tokenId, _tokenOwner);
    }

    /**
     * @dev Step 2b. (BATCH)
     * Cost: ~40,000 gas
     */
    function adminVerifyRedemptionCodeBatch(address _tokensOwner, uint256 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStepBatch(_tokensOwner, 2) {
            if (_code != _batchRedemptionData[_tokensOwner][0]) {
                _errMsg("code mismatch");
            }
            _batchRedemptionData[_tokensOwner][1] = 3;
            emit RedeemerAdminApproveBatch(_tokensOwner);
    }

    /**
     * @dev Step 3.
     * User verifies info submitted by submitting 
     * confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 _tokenId, uint256 _code)
        external
        redemptionStep(_tokenId, 3) {
            if (_code != _redemptionData[_tokenId][0]) {
                _errMsg("code mismatch");
            }
            _redemptionData[_tokenId][1] = 4;
            emit RedeemerUserVerify(_tokenId, msg.sender);
    }

    /**
     * @dev Step 3. (BATCH)
     * Cost: ~37,000 gas
     */
    function userVerifyRedemptionBatch(uint256 _code)
        external
        redemptionStepBatch(msg.sender, 3) {
            if (_code != _batchRedemptionData[msg.sender][0]) {
                _errMsg("code mismatch");
            }
            _batchRedemptionData[msg.sender][1] = 4;
            emit RedeemerUserVerifyBatch(msg.sender);
    }

    /**
     * @dev Step 4.
     * User submits one last confirmation to lock the token 
     * forever and have physical item shipped to them. There will be a final 
     * fee to pay at this step to cover shipping and insurance costs. 
     * Fee will need to be done externally, any internal implementation 
     * risks being unreliable without easy access to recent external data. 
     * At best, a minimum enforcement amount is set to be payable. To 
     * prevent users underpaying, an aminFinalApproval call is done.
     */
    function userFinishRedemption(uint256 _tokenId)
        external payable
        redemptionStep(_tokenId, 4) {
            /*
            address _contractPriceFeed = C9Token(tokenContract).contractPriceFeed();
            uint256 _minRedeemWei = IC9EthPriceFeed(_contractPriceFeed).getTokenWeiPrice(20);
            if (msg.value < _minRedeemWei) {
                revert("C9Redeemer: incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                revert("C9Redeemer: payment failure");
            }
            */
            _redemptionData[_tokenId][1] = 5;
            emit RedeemerUserFinalize(_tokenId, msg.sender, msg.value);
    }

    /**
     * @dev Step 4. (BATCH)
     */
    function userFinishRedemptionBatch()
        external payable
        redemptionStepBatch(msg.sender, 4) {
            /*
            address _contractPriceFeed = C9Token(tokenContract).contractPriceFeed();
            uint256 _minRedeemWei = IC9EthPriceFeed(_contractPriceFeed).getTokenWeiPrice(20*_batchSize);
            if (msg.value < _minRedeemWei) {
                revert("C9Redeemer: incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                revert("C9Redeemer: payment failure");
            }
            */
            _batchRedemptionData[msg.sender][1] = 5;
            emit RedeemerUserFinalizeBatch(msg.sender, msg.value);
    }

    /**
     * @dev Step 5.
     * Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(uint256 _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenId, 5)
        notFrozen() {
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            IC9Token(contractToken).redeemFinish(_tokenId);
            _removeRedemptionData(_tokenId);
            emit RedeemerAdminApprove(_tokenId, _tokenOwner);
    }

    /**
     * @dev Step 5. (BATCH)
     * Cost: ~113,000 gas for batch of 10.
     */
    function adminFinalApprovalBatch(address _tokensOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStepBatch(_tokensOwner, 5)
        notFrozen() {
            IC9Token(contractToken).redeemBatchFinish(_batchRedemptionData[_tokensOwner]);
            _removeBatchRedemptionData(_tokensOwner);
            emit RedeemerAdminApproveBatch(_tokensOwner);
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
}