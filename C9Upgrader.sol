// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";


contract C9Upgrader is C9Struct, C9OwnerControl {
    address public immutable contractToken;
    uint8 public tokensUpgradePrice = 100; //usd

    event Upgraded(
        address indexed buyer,
        uint256 indexed tokenId,
        uint8 indexed price
    );

    constructor(address _contractToken) {
        contractToken = _contractToken;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = IC9Token(contractToken).ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) revert("C9Redeemer: unauthorized");
        _;
    }

    /**
     * @dev Allows the token holder to upgrade their token.
     */
    function upgradeToken(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
        notFrozen() {
            if (IC9Token(contractToken).tokenUpgraded(_tokenId)) {
                revert("C9Upgrader: token already upgraded");
            }
            if (IC9Token(contractToken).preRedeemable(_tokenId)) {
                revert("C9Upgrader: token not upgradable during pre-redeemable period");
            }
            address priceFeedContract = C9Token.contractPriceFeed();
            uint256 upgradeWeiPrice = IC9EthPriceFeed(priceFeedContract).getTokenWeiPrice(tokensUpgradePrice);
            if (msg.value != upgradeWeiPrice) {
                revert("C9Upgrader: incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if(!success) {
                revert("C9Upgrader: payment failure");
            }
            IC9Token(contractToken).setTokenUpgraded(_tokenId);
            emit Upgraded(msg.sender, _tokenId, tokensUpgradePrice);
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setTokensUpgradePrice(uint8 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (tokensUpgradePrice == _price) {
                revert("C9Token: price already set");
            }
            tokensUpgradePrice = _price;
    }

}