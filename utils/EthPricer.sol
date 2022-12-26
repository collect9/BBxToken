// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IC9EthPriceFeed.sol";

contract C9EthPriceFeed is IC9EthPriceFeed, Ownable {
    AggregatorV3Interface private priceFeed;

    /**
     * Aggregator: ETH/USD
     * Network: Goerli
     * Address: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
     * Network: Mainnet
     * Address: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
     */
    constructor(address _priceFeedAddress) {
        setPriceFeed(_priceFeedAddress);
    }

    /**
     * Returns the token price in ETH to 8 decimals.
     * Front end will need to convert to proper decimals.
     */
    function getLatestETHUSDPrice()
        public view override
        returns (uint256) {
            (,int256 price,,uint256 timeStamp,) = priceFeed.latestRoundData();
            uint256 _ds = block.timestamp - timeStamp;
            if (_ds > MAX_TIME_DELAY) revert PriceFeedDated(MAX_TIME_DELAY, _ds);
            return uint256(price);
    }

    /**
     * Converts the token USD price to ETH wei integer format.
     * The front-end will need to convert this into ETH decimal format.
     */
    function getTokenWeiPrice(uint256 _tokenUSDPrice)
        external view override
        returns (uint256 tokenETHPrice) {
            uint256 tokenUSDPrice = _tokenUSDPrice*10**18;
            uint256 etherPriceUSD = getLatestETHUSDPrice()*10**10;
            tokenETHPrice = (tokenUSDPrice*10**18)/etherPriceUSD; //wei
    }

    /**
     * Allows price feed address change in the future if needed.
     */
    function setPriceFeed(address _address)
    public
        onlyOwner {
            priceFeed = AggregatorV3Interface(_address);
    }
}