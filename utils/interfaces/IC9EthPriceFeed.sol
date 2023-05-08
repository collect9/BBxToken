// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

uint256 constant MAX_TIME_DELAY = 3600;

interface IC9EthPriceFeed {
    function getLatestETHUSDPrice()
    external view
    returns (uint256, uint256);

    function getTokenWeiPrice(uint256 _tokenUSDPrice)
    external view
    returns (uint256 tokenETHPrice);

    function safeGetTokenWeiPrice(uint256 tokenUSDPrice)
    external view
    returns (uint256 tokenETHPrice) ;
}