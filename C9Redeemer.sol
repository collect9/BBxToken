// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Register.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {    
    function cancelRedemption(uint256 _tokenId) external;
    function getRedemptionStep(uint256 _tokenId) external view returns (uint32);
    function startRedemption(uint256 _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32[2]) _redemptionData; //code, step

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
    event RedeemerUserFinalize(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );

    address public contractRegistrar;
    address public contractToken;
    
    constructor(){}

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            _errMsg("unauthorized");
        }
        _;
    }

    modifier redemptionStep(uint256 _tokenId, uint32 _step) {
        if (_frozen) {
            _errMsg("contract frozen");
        }
        uint32 _expected = _redemptionData[_tokenId][1];
        if (_step != _expected) {
            _errMsg("wrong redemption step");
        }
        _;
    }

    modifier tokenLock(uint256 _tokenId) {
        bool _lock = IC9Token(contractToken).tokenLocked(_tokenId);
        if (_lock != true) {
            _errMsg("token not locked");
        }
        _;
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Redeemer: ", message)));
    }

    function getRedemptionStep(uint256 _tokenId)
        external view override
        returns(uint32) {
            return _redemptionData[_tokenId][1];
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     */
    function cancelRedemption(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLock(_tokenId) {
            _removeRedemptionInfo(_tokenId);
            emit RedeemerCancel(_tokenId, msg.sender, _redemptionData[_tokenId][1]);
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

    /**
     * @dev Step 1. User initializes redemption
     */
    function startRedemption(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 0) {
            // Check if already registered
            address _registerOwner = IC9Registrar(contractRegistrar).getRegisteredOwner(_tokenId);
            if (_registerOwner != address(0)) {
                // If registered jump to step 4
                _redemptionData[_tokenId][1] = 4;
                emit RedeemerInit(_tokenId, msg.sender, true);
            }
            else {
                // Else move to next step
                _redemptionData[_tokenId][1] = 1;
                emit RedeemerInit(_tokenId, msg.sender, false);
            }
    }

    /**
     * @dev Step 2. User submits info and waits for email.
     */
    function genRedemptionCode(uint256 _tokenId)
        external
        isOwner(_tokenId)
        redemptionStep(_tokenId, 1) {
            uint32 _randomCode = uint32(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            block.number,
                            msg.sender
                        )
                    )
                )
            ) % 10**6;
            _redemptionData[_tokenId][0] = _randomCode;
            _redemptionData[_tokenId][1] = 2;
            emit RedeemerGenCode(_tokenId, msg.sender);
    }

    /**
     * @dev Step 2b. Admin/backend retrieves info.
     */
    function adminGetRedemptionCode(uint256 _tokenId)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint32) {
            return _redemptionData[_tokenId][0];
    }
    /**
     * @dev Step 2c. Admin confirms receipt of info by sending code 
     * to email specified in info, along with the rest of the info 
     * for the user to verify.
     */
    function adminVerifyRedemptionCode(uint256 _tokenId, uint32 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenId, 2) {
            if (_code != _redemptionData[_tokenId][0]) {
                _errMsg("code incorrect");
            }
            _redemptionData[_tokenId][1] = 3;
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            emit RedeemerAdminApprove(_tokenId, _tokenOwner, 2);
    }

    /**
     * @dev Step 3. User verifies info submitted by submitting 
     * confirmation code.
     */
    function userVerifyRedemption(uint256 _tokenId, uint32 _code)
        external
        isOwner(_tokenId)
        redemptionStep(_tokenId, 3) {
            if (_code != _redemptionData[_tokenId][0]) {
                _errMsg("code incorrect");
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
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 5) {
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
                _errMsg("address already set");
            }
            contractRegistrar = _address;
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractToken(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractToken == _address) {
                _errMsg("address already set");
            }
            contractToken = _address;
            _grantRole(NFTCONTRACT_ROLE, contractToken);
    }
}