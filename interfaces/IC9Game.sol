// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./../utils/interfaces/IC9ERC721Base.sol";

uint256 constant POS_ROUND_ID = 160;
uint256 constant POS_SEED = 176;

uint256 constant WPOS_WINNING_ID = 160;
uint256 constant WPOS_GAMESIZE = 176;
uint256 constant WPOS_INDICES = 184;

interface IC9Game is IC9ERC721Base {

    function currentPotSplit(uint256 _gameSize)
    external view
    returns(uint256 payout0, uint256 payout1);

    function currentRoundId()
    external view
    returns (uint256);

    function priorWinnerData(uint256 tokenId)
    external view
    returns (address priorWinner, uint256 winningNumber, uint256[] memory _indices);

    function viewIndicesTokenIds(uint256 tokenId, uint256[] memory _sortedIndices)
    external view
    returns (uint256[] memory);

    function tokenData(uint256 tokenId)
    external view
    returns (address tokenOwner, uint256 tokenRoundId, uint256 randomSeed);

    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
    external view 
    returns (uint256[] memory);
}