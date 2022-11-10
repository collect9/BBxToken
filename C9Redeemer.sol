// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./C9Token2.sol";
import "./utils/Pricer.sol";

interface IC9Redeemer {
    function cancelRedemption(uint256 _tokenId) external;
    function storeRedemptionInfo(uint256 _tokenId, string calldata _info) external;
}

contract C9Redeemer is IC9Redeemer, AccessControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    mapping(uint256 => string) private _redemptionInfo;
    mapping(uint256 => uint256) private _redemptionCode;
    mapping(uint256 => bool) private _redemptionVerified;
    address public priceFeedContract;
    address public tokenContract;

    event RedemptionEvent(
        address indexed tokenOwner,
        uint256 indexed tokenId,
        string indexed status
    );

    constructor(address _priceFeedContract, address _tokenContract) {
            _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
            _grantRole(NFTCONTRACT_ROLE, _tokenContract);
            priceFeedContract = _priceFeedContract;
            tokenContract = _tokenContract;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = C9Token(tokenContract).ownerOf(_tokenId);
        require(msg.sender == _tokenOwner, "Caller is not token owner");
        _;
    }

    modifier redemptionStarted(uint256 _tokenId) {
        bool _lock = IC9Token(tokenContract).tokenRedemptionLock(_tokenId);
        require(_lock, "Token redemption not started for this _tokenId");
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
        redemptionStarted(_tokenId) {
            removeRedemptionInfo(_tokenId);
    }

    // 4. User submits one last confirmation to lock the token forever and have item shipped
    function finishRedemption(uint256 _tokenId)
        external
        isOwner(_tokenId)
        redemptionStarted(_tokenId) {
            IC9Token(tokenContract).redeemFinish(_tokenId);
            removeRedemptionInfo(_tokenId);
    }

    // 2. Admin retrieves info, sends email with code
    function getRedemptionInfo(uint256 _tokenId)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256, string memory) {
            return (_redemptionCode[_tokenId], _redemptionInfo[_tokenId]);
    }

    /**
     * @dev Generates a random number < 10**12. This number is 
     * used as the 'verification code' in the userVerifyRedemption() 
     * step.
     */
    function randomCode()
        internal view
        returns (uint256) {
            return uint256(
                keccak256(
                    abi.encodePacked(
                        IC9EthPriceFeed(priceFeedContract).getLatestETHUSDPrice(),
                        block.difficulty,
                        block.number,
                        msg.sender
                    )
                )
            ) % 10**12;
    }

    function removeRedemptionInfo(uint256 _tokenId) internal {
        delete _redemptionCode[_tokenId];
        delete _redemptionInfo[_tokenId];
        delete _redemptionVerified[_tokenId];
    }

    // 1. User submits info and waits for email
    function storeRedemptionInfo(uint256 _tokenId, string calldata _info)
        external override
        isOwner(_tokenId)
        redemptionStarted(_tokenId) {
            _redemptionInfo[_tokenId] = _info; // some kind of encrypted info
            _redemptionCode[_tokenId] = randomCode(); // generate random code
            emit RedemptionEvent(msg.sender, _tokenId, "STORED");
    }

    // 3. User verifies information by submitting confirmation code as payment amount
    function userVerifyRedemption(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
        redemptionStarted(_tokenId) {
            require(msg.value == _redemptionCode[_tokenId], "Incorrect amount of ETH sent to verify redemption info");
            _redemptionVerified[_tokenId] = true;
            emit RedemptionEvent(msg.sender, _tokenId, "VERIFIED");
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setPriceFeedContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            priceFeedContract = _address;
    }
}