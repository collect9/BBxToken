// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "./C9Token2.sol";

error CodeMismatch(bool admin);
error IncorrectRedemptionStep(uint256 tokenId, uint32 expected, uint8 tried);

interface IC9Redeemer {
    function cancelRedemption(uint256 _tokenId) external;
    function getRedemptionStep(uint256 _tokenId) external view returns (uint32);
    function startRedemption(uint256 _tokenId) external;
}

/*
2. Final value fee - maybe make it part of the confirmation step? If the code is 
a small amount of wei, then final value fee can be combined with it... i.e if 
fee is 0.01 ETH, then confirmation will be 0.01 ETH + CONFIRMATION AMOUNT... i,e.
0.0100001583728458524.... but how to enforce the 0.01 part which will vary?

Can also make it based on token insured value that can be stored. But it needs to 
be capped otherwise users can abuse an make token unredeemed due to very high FVF.
However if that happens this contract can always be upgraded.
*/

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant INFOVIEWER_ROLE = keccak256("INFOVIEWER_ROLE");
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32) _redemptionCode;
    mapping(uint256 => uint8) _redemptionStep;

    event RedeemerAdminVerify(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedeemerCancel(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedeemerFinalize(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedeemerGenCode(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedeemerInit(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedeemerUserVerify(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );

    address private viewerAddress;
    address public tokenContract;
    /**
     * @dev priceFeed and tokenContracts will already exist 
     * before the deployment of this one.
     */
    constructor() {
        _grantRole(INFOVIEWER_ROLE, msg.sender); //remove later
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = IC9Token(tokenContract).ownerOf(_tokenId);
        if(msg.sender != _tokenOwner) revert Unauthorized(msg.sender, _tokenOwner);
        _;
    }

    modifier redemptionStep(uint256 _tokenId, uint8 _step) {
        uint32 _expected = _redemptionStep[_tokenId];
        if(_step != _expected) revert IncorrectRedemptionStep(_tokenId, _expected, _step);
        _;
    }

    modifier tokenLock(uint256 _tokenId) {
        bool _lock = IC9Token(tokenContract).tokenRedemptionLock(_tokenId);
        if(_lock != true) revert RedemptionPending(_tokenId, false);
        _;
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
            removeRedemptionInfo(_tokenId);
            emit RedeemerCancel(msg.sender, _tokenId);
    }

    /**
     * @dev Function the front end will need so it knows which 
     * button to have enabled.
     */
    function getRedemptionStep(uint256 _tokenId)
        external view override
        onlyRole(INFOVIEWER_ROLE)
        returns (uint32) {
            return _redemptionStep[_tokenId];
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
     * @dev Step 1. User initializes redemption
     */
    function startRedemption(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 0) {
            _redemptionStep[_tokenId] = 1;
            emit RedeemerInit(msg.sender, _tokenId);
    }

    /**
     * @dev Step 2. User submits info and waits for email.
     */
    function genRedemptionCode(uint256 _tokenId)
        external
        isOwner(_tokenId)
        tokenLock(_tokenId)
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
            _redemptionCode[_tokenId] = _randomCode;
            _redemptionStep[_tokenId] = 2;
            emit RedeemerGenCode(msg.sender, _tokenId);
    }

    /**
     * @dev Step 2b. Admin/backend retrieves info.
     */
    function adminGetRedemptionCode(uint256 _tokenId)
        external view
        onlyRole(INFOVIEWER_ROLE)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 2)
        returns (uint32) {
            return _redemptionCode[_tokenId];
    }
    /**
     * @dev Step 2c. Admin confirms receipt of info by sending code 
     * to email specified in info, along with the rest of the info 
     * for the user to verify.
     */
    function adminVerifyRedemptionCode(uint256 _tokenId, uint32 _code)
        external
        onlyRole(INFOVIEWER_ROLE)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 2) {
            if (_code == _redemptionCode[_tokenId]) {
                revert CodeMismatch(true);
            }
            _redemptionStep[_tokenId] = 3;
            emit RedeemerAdminVerify(msg.sender, _tokenId);
    }

    /**
     * @dev Step 3. User verifies info submitted by submitting 
     * confirmation code.
     */
    function userVerifyRedemption(uint256 _tokenId, uint32 _code)
        external
        isOwner(_tokenId)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 3) {
            if (_code == _redemptionCode[_tokenId]) {
                revert CodeMismatch(false);
            }
            _redemptionStep[_tokenId] = 4;
            emit RedeemerUserVerify(msg.sender, _tokenId);
    }

    /**
     * @dev Step 4. User submits one last confirmation to lock the token 
     * forever and have physical item shipped to them. There will be a final 
     * fee to pay at this step to cover shipping and insurance costs.
     */
    function finishRedemption(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
        tokenLock(_tokenId)
        redemptionStep(_tokenId, 4) {
            require(msg.value > 0, "C9Redeemer: no eth sent");
            (bool success,) = payable(owner).call{value: msg.value}("");
            if (!success) {
                revert PayementFailure(msg.sender, owner, msg.value);
            }
            IC9Token(tokenContract).redeemFinish(_tokenId);
            removeRedemptionInfo(_tokenId);
            emit RedeemerFinalize(msg.sender, _tokenId);
    }

    /**
     * @dev Updates the token contract address.
     */
    function setTokenContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            tokenContract = _address;
            _grantRole(NFTCONTRACT_ROLE, tokenContract);
    }

    /**
     * @dev Updates the token contract address.
     */
    function setViewerContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            viewerAddress = _address;
            _grantRole(INFOVIEWER_ROLE, viewerAddress);
    }
}