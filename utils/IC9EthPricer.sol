// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

uint256 constant MAX_TIME_DELAY = 3600;

error InvalidPaymentAmount(uint256 expected, uint256 received); //0x05dbe7d3
error PaymentFailure(); //0x29292fa2
error PriceFeedDated(uint256 maxDelay, uint256 received); //0xb8875fad

interface IC9EthPriceFeed {
    function getLatestETHUSDPrice() external view returns (uint256);
    function getTokenWeiPrice(uint256 _tokenUSDPrice) external view returns (uint256 tokenETHPrice);
}