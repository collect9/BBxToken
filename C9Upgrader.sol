// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Token2.sol";
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

    /**
     * @dev Allows the token holder to upgrade their token.
     */
    function upgradeToken(uint256 _tokenId, uint256 _upgradeLevel)
        external payable
        isOwner(_tokenId)
        notFrozen() {
            if (IC9Token(contractToken).tokenUpgraded(_tokenId)) {
                _errMsg("token already upgraded");
            }
            uint256 _upgradePrice = baseUpgradePrice * _upgradeLevel;
            uint256 upgradeWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_upgradePrice);
            if (msg.value != upgradeWeiPrice) {
                _errMsg("incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if(!success) {
                _errMsg("payment failure");
            }
            IC9Token(contractToken).setTokenUpgraded(_tokenId, _upgradeLevel);
            emit Upgraded(msg.sender, _tokenId, _upgradePrice);
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setBaseUpgradePrice(uint8 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (tokensUpgradePrice == _price) {
                _errMsg("price already set");
            }
            tokensUpgradePrice = _price;
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