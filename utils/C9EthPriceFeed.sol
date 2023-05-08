// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./../abstract/C9Errors.sol";
import "./interfaces/IC9EthPriceFeed.sol";

contract C9EthPriceFeed is IC9EthPriceFeed, Ownable {
    AggregatorV3Interface private _priceFeed;

    /**
     * Aggregator: ETH/USD
     * Network: Goerli
     * Address: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
     * Network: Sepolia
     * Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     * Network: Mainnet
     * Address: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
     */
    constructor(address priceFeedAddress) {
        setPriceFeed(priceFeedAddress);
    }

    /**
     * @dev Returns the token price in ETH to 8 decimals.
     * Front end will need to convert to proper decimals.
     */
    function getLatestETHUSDPrice()
    public view
    returns (uint256, uint256) {
        (,int256 price,,uint256 timestamp,) = _priceFeed.latestRoundData();
        return (uint256(price), timestamp);
    }

    /**
     * @dev Converts the token USD price to wei uint format.
     * The front-end will need to convert this into ETH decimal format.
     *
     * @param tokenUSDPrice The usd value to convert to wei.
     * @return tokenETHPrice The wei value of the tokenUSDPrice input.
     * @notice Unchecked because there shouldn't be any possible under
     * or overflow conditions purely from uint division.
     */
    function getTokenWeiPrice(uint256 tokenUSDPrice)
    external view
    returns (uint256 tokenETHPrice) {
        (uint256 etherPriceUSD,) = getLatestETHUSDPrice();
        unchecked {
            tokenETHPrice = (tokenUSDPrice*10**26)/etherPriceUSD; //wei
        }
    }

    /**
     * @dev Safe version of getTokenWeiPrice(...) that checks to 
     * ensure the last price update is recent enough.
     *
     * @param tokenUSDPrice The usd value to convert to wei.
     * @return tokenETHPrice The wei value of the tokenUSDPrice input.
     * @notice Unchecked because there shouldn't be any possible under
     * or overflow conditions purely from uint division.
     */
    function safeGetTokenWeiPrice(uint256 tokenUSDPrice)
    external view
    returns (uint256 tokenETHPrice) {
        (uint256 etherPriceUSD,uint256 timestamp) = getLatestETHUSDPrice();
        // Make sure the price is recently enough updated
        uint256 _ds = block.timestamp - timestamp;
        if (_ds > MAX_TIME_DELAY) {
            revert PriceFeedDated(MAX_TIME_DELAY, _ds);
        }
        unchecked {
            tokenETHPrice = (tokenUSDPrice*10**26)/etherPriceUSD; //wei
        }
    }

    /**
     * @dev Allows price feed address change in the future if needed.
     *
     * @param _address The new price feed address.
     */
    function setPriceFeed(address _address)
    public
    onlyOwner {
        _priceFeed = AggregatorV3Interface(_address);
    }
}