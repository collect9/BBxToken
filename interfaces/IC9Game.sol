// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./../utils/interfaces/IC9ERC721Base.sol";

interface IC9Game is IC9ERC721Base {

    function currentRoundId()
    external view
    returns (uint256);

    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
    external view 
    returns (uint256[] memory);
}