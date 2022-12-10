// SPDX-License-Identifier: MIT
pragma solidity >0.8.10;
import "./C9OwnerControl.sol";
import "./C9Token.sol";
import "./utils/EthPricer.sol";


contract C9Upgrader is C9Struct, C9OwnerControl {
    address public contractPricer;
    address public immutable contractToken;
    uint16 public baseUpgradePrice = 100; //usd

    event Upgraded(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 indexed price
    );

    constructor(address _contractToken) {
        contractToken = _contractToken;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = IC9Token(contractToken).ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) _errMsg("unauthorized");
        _;
    }

    /**
     * @dev Reduces revert error messages fee slightly. This will 
     * eventually be replaced by customError when Ganache 
     * supports them.
     */
    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Upgrader: ", message)));
    }

    function getUpgradePrice(uint256 _upgradeLevel) 
        public view
        returns (uint256 _upgradePrice) {
            _upgradePrice = baseUpgradePrice * _upgradeLevel;
    }

    /**
     * @dev Allows the token holder to upgrade their token.
     */
    function upgradeToken(uint256 _tokenId, uint256 _upgradeLevel)
        external payable
        isOwner(_tokenId)
        notFrozen() {
            uint256[18] memory _uTokenData = IC9Token(contractToken).getTokenParams(_tokenId);
            if (_uTokenData[0] != 0) {
                _errMsg("token already upgraded");
            }
            uint256 _upgradePrice = getUpgradePrice(_upgradeLevel);
            uint256 upgradeWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_upgradePrice);
            if (msg.value != upgradeWeiPrice) {
                _errMsg("incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if(!success) {
                _errMsg("payment failure");
            }
            IC9Token(contractToken).setTokenUpgraded(_tokenId, _upgradeLevel);
            emit Upgraded(_tokenId, msg.sender, _upgradePrice);
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setBaseUpgradePrice(uint16 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (baseUpgradePrice == _price) {
                _errMsg("price already set");
            }
            baseUpgradePrice = _price;
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
}