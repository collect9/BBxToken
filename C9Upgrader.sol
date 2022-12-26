// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./abstract/C9Struct.sol";
import "./interfaces/IC9Token.sol";
import "./utils/IC9EthPriceFeed.sol";

contract C9Upgrader is C9Struct, C9OwnerControl {
    address private contractPricer;
    address private immutable contractToken;
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
        if (msg.sender != _tokenOwner) revert Unauthorized();
        _;
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(address pricer, address token) {
            pricer = contractPricer;
            token = contractToken;
    } 

    /**
     * @dev Allows the token holder to upgrade their token.
     */
    function upgradeToken(uint256 _tokenId)
        external payable
        isOwner(_tokenId)
        notFrozen() {
            uint256 upgradeWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(baseUpgradePrice);
            if (msg.value != upgradeWeiPrice) {
                revert InvalidPaymentAmount(upgradeWeiPrice, msg.value);
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if(!success) {
                revert PaymentFailure();
            }
            IC9Token(contractToken).setTokenUpgraded(_tokenId);
            emit Upgraded(_tokenId, msg.sender, baseUpgradePrice);
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setBaseUpgradePrice(uint16 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (baseUpgradePrice == _price) {
                revert ValueAlreadySet();
            }
            baseUpgradePrice = _price;
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractPricer == _address) {
                revert AddressAlreadySet();
            }
            contractPricer = _address;
    }
}