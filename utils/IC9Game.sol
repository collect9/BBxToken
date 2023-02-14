// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IC9Game {
    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
    external view 
    returns (uint256[] memory);
}