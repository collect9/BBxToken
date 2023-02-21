// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./../utils/interfaces/IC9ERC721Base.sol";

uint256 constant POS_ROUND_ID = 176;
uint256 constant POS_SEED = 192;

interface IC9Game is IC9ERC721Base {

    function currentRoundId()
    external view
    returns (uint256);

    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
    external view 
    returns (uint256[] memory);
}