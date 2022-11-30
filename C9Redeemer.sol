// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Registrar.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {    
    function cancel(uint256 _tokenId) external;
    function getRedemptionStep(uint256 _tokenId) external view returns (uint256);
    function start(uint256 _tokenId) external;
    function startBatch(address _tokensOwner, uint256[] calldata _tokenId, uint256 batchSize) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32[2]) _redemptionData; //code, step
    mapping(address => uint32[]) _batchRedemptionData; //code, step, token1, token2..., tokenN

    event RedeemerAdminApprove(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint32 indexed redemptionStep
    );
    event RedeemerCancel(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint32 indexed redemptionStep
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
    event RedeemerInitBatch(
        address indexed tokenOwner,
        uint256 batchSize,
        bool indexed registered
    );
    event RedeemerUserFinalize(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        uint256 indexed tokenId,
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
        if (_step != _batchRedemptionData[_tokenOwner][1]) {
            _errMsg("wrong batch redemption step");
        }
        _;
    }

    modifier tokenLocked(uint256 _tokenId) {
        if (!IC9Token(contractToken).tokenLocked(_tokenId)) {
            _errMsg("token not locked");
        }
        _;
    }

    modifier tokenLockedBatch(uint256[] calldata _tokenId, uint256 _batchSize) {
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
    function _removeRedemptionInfo(uint256 _tokenId)
        internal {
            delete _redemptionData[_tokenId];
    }

    function getRedemptionStep(uint256 _tokenId)
        external view override
        returns(uint256) {
            return uint256(_redemptionData[_tokenId][1]);
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
            _removeRedemptionInfo(_tokenId);
            emit RedeemerCancel(_tokenId, msg.sender, _redemptionData[_tokenId][1]);
    }

    /**
     * @dev Step 1. User initializes redemption
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
                uint256 _randomCode = uint256(
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
                _redemptionData[_tokenId][0] = uint32(_randomCode);
                _redemptionData[_tokenId][1] = 2;
                emit RedeemerInit(_tokenId, msg.sender, false);
            }
    }

    function startBatch(address _tokensOwner, uint256[] calldata _tokenId, uint256 batchSize)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLockedBatch(_tokenId, batchSize)
        redemptionStepBatch(_tokensOwner, 0)
        notFrozen() {
            // Check to make sure all tokenId are of the same owner - make batch ownerOf?
            for (uint256 i; i<batchSize; i++) {
                if (C9Token(contractToken).ownerOf(_tokenId[i]) != _tokensOwner) {
                    _errMsg("unauthorized");
                }
            }
            _incrementer += uint96(batchSize);

            bool _registerOwner = IC9Registrar(contractRegistrar).addressRegistered(_tokensOwner);
            if (_registerOwner) {
                // If registered jump to step 4
                _batchRedemptionData[_tokensOwner].push(0); // dummy code
                _batchRedemptionData[_tokensOwner].push(4);
                emit RedeemerInitBatch(msg.sender, batchSize, true);
            }
            else {
                // Else move to next step
                uint256 _randomCode = uint256(
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
                _batchRedemptionData[_tokensOwner].push(uint32(_randomCode));
                _batchRedemptionData[_tokensOwner].push(2);
                emit RedeemerInitBatch(msg.sender, batchSize, false);
            }
            for (uint256 i; i<batchSize; i++) {
                _batchRedemptionData[_tokensOwner].push(uint32(_tokenId[i]));
            }
    }

    /**
     * @dev Step 2a. Admin/backend retrieves info.
     */
    function adminGetRedemptionCode(uint256 _tokenId)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint32) {
            return _redemptionData[_tokenId][0];
    }
    /**
     * @dev Step 2b. Admin confirms receipt of info by sending code 
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
            emit RedeemerAdminApprove(_tokenId, _tokenOwner, 2);
    }

    /**
     * @dev Step 3. User verifies info submitted by submitting 
     * confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 _tokenId, uint256 _code)
        external
        isOwner(_tokenId)
        redemptionStep(_tokenId, 3) {
            if (_code != _redemptionData[_tokenId][0]) {
                _errMsg("code mismatch");
            }
            _redemptionData[_tokenId][1] = 4;
            emit RedeemerUserVerify(_tokenId, msg.sender);
    }

    /**
     * @dev Step 4. User submits one last confirmation to lock the token 
     * forever and have physical item shipped to them. There will be a final 
     * fee to pay at this step to cover shipping and insurance costs. 
     * Fee will need to be done externally, any internal implementation 
     * risks being unreliable without easy access to recent external data. 
     * At best, a minimum enforcement amount is set to be payable. To 
     * prevent users underpaying, an aminFinalApproval call is done.
     */
    function userFinishRedemption(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
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
     * @dev Step 5. Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(uint256 _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenLocked(_tokenId)
        redemptionStep(_tokenId, 5)
        notFrozen() {
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            IC9Token(contractToken).redeemFinish(_tokenId);
            _removeRedemptionInfo(_tokenId);
            emit RedeemerAdminApprove(_tokenId, _tokenOwner, 5);
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