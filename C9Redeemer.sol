// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "./C9Token2.sol";

interface IC9Redeemer {
    function cancelRedemption(uint256 _tokenId) external;
    function genRedemptionCode(uint256 _tokenId) external;
    function getRedemptionCode(uint256 _tokenId) external view returns (uint32);
}

/*
2. Final value fee - maybe make it part of the confirmation step? If the code is 
a small amount of wei, then final value fee can be combined with it... i.e if 
fee is 0.01 ETH, then confirmation will be 0.01 ETH + CONFIRMATION AMOUNT... i,e.
0.0100001583728458524.... but how to enforce the 0.01 part which will vary?
*/

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant INFO_VIEWER = keccak256("INFO_VIEWER");
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32) private _redemptionCode;
    mapping(uint256 => uint8) private _redemptionStep;
    event RedemptionEvent(
        address indexed tokenOwner,
        uint256 indexed tokenId,
        string indexed status
    );

    address public tokenContract;
    /**
     * @dev priceFeed and tokenContracts will already exist 
     * before the deployment of this one.
     */
    constructor(address _tokenContract) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(NFTCONTRACT_ROLE, _tokenContract);
        tokenContract = _tokenContract;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = C9Token(tokenContract).ownerOf(_tokenId);
        require(msg.sender == _tokenOwner, "C9Redeemer: msg sender is not token owner");
        _;
    }

    modifier redemptionStarted(uint256 _tokenId) {
        bool _lock = IC9Token(tokenContract).tokenRedemptionLock(_tokenId);
        require(_lock, "C9Redeemer: token redemption not started for this _tokenId");
        _;
    }

    modifier redemptionStep(uint256 _tokenId, uint8 _step) {
        require(_step == _redemptionStep[_tokenId], "C9Redeemer: incorrect redemption step");
        _;
    }

    /**
     * @dev Step 2a. Admin/backend retrieves info.
     */
    function adminGetRedemptionCode(uint256 _tokenId)
        external
        onlyRole(INFO_VIEWER)
        redemptionStarted(_tokenId)
        redemptionStep(_tokenId, 2)
        returns (uint32) {
            emit RedemptionEvent(msg.sender, _tokenId, "ADMIN GET CODE");
            return _redemptionCode[_tokenId];
    }
    /**
     * @dev Step 2b. Admin confirms receipt of code (and send code to 
     * user with email address provided).
     */
    function adminVerifyRedemptionCode(uint256 _tokenId, uint32 _code)
        external
        onlyRole(INFO_VIEWER)
        redemptionStarted(_tokenId)
        redemptionStep(_tokenId, 2) {
            require(_code == _redemptionCode[_tokenId], "C9Redeemer: incorrect verification code");
            _redemptionStep[_tokenId] = 3;
            emit RedemptionEvent(msg.sender, _tokenId, "ADMIN SENT CODE");
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     */
    function cancelRedemption(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStarted(_tokenId) {
            removeRedemptionInfo(_tokenId);
            emit RedemptionEvent(msg.sender, _tokenId, "USER CANCELED");
    }

    /**
     * @dev Step 4. User submits one last confirmation to lock the token 
     * forever and have physical item shipped to them. There will be a final 
     * fee to pay at this step to cover shipping and insurance costs.
     */
    function finishRedemption(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
        redemptionStarted(_tokenId)
        redemptionStep(_tokenId, 4) {
            require(msg.value > 0, "C9Redeemer: no eth sent");
            (bool success,) = payable(owner).call{value: msg.value}("");
            require(success, "C9Redeemer: unable to send ethereum");
            IC9Token(tokenContract).redeemFinish(_tokenId);
            removeRedemptionInfo(_tokenId);
            emit RedemptionEvent(msg.sender, _tokenId, "USER FINALIZED");
    }

    /**
     * @dev Step 1. User submits info and waits for email.
     */
    function genRedemptionCode(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStarted(_tokenId) {
            require(_redemptionStep[_tokenId] < 2, "C9Redeemer: redemption already started");
            _redemptionCode[_tokenId] = randomCode();
            _redemptionStep[_tokenId] = 2;
            emit RedemptionEvent(msg.sender, _tokenId, "USER CODE GEN");
    }

    /**
     * @dev Function the front end will need so it knows which 
     * button to have enabled.
     */
    function getRedemptionCode(uint256 _tokenId)
        external view override
        onlyRole(INFO_VIEWER)
        redemptionStarted(_tokenId)
        returns (uint32) {
            return _redemptionStep[_tokenId];
    }

    /**
     * @dev Generates a pseudo-random number < 10**6. This number is 
     * used as the 'verification code' in the userVerifyRedemption() 
     * step.
     */
    function randomCode()
        internal view
        returns (uint32) {
            return uint32(uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        block.number,
                        msg.sender
                    )
                )
            )) % 10**6;
    }

    /**
     * @dev Removes any redemption info after redemption is finished 
     * or if token own calls this contract (from the token contract) 
     * having caneled redemption.
     */
    function removeRedemptionInfo(uint256 _tokenId) internal {
        delete _redemptionCode[_tokenId];
        delete _redemptionStep[_tokenId];
    }

    /**
     * @dev Step 3. User verifies information submitted by submitting 
     * confirmation code.
     */
    function userVerifyRedemption(uint256 _tokenId, uint32 _code)
        external
        isOwner(_tokenId)
        redemptionStarted(_tokenId)
        redemptionStep(_tokenId, 3) {
            require(_code == _redemptionCode[_tokenId], "C9Redeemer: incorrect verification code");
            _redemptionStep[_tokenId] = 4;
            emit RedemptionEvent(msg.sender, _tokenId, "USER VERIFIED");
    }
}