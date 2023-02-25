// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./interfaces/IC9Game.sol";
import "./interfaces/IC9GameMetaData.sol";
import "./utils/Helpers.sol";

contract C9GameMetaData is IC9GameMetaData {

    bytes constant DESC = ""
    "Each NFT in this collection is a playing board for the Collect9 ConnectX game. "

    "ConnectX is a game inspired by both Bingo and Connect4(TM). Playing boards are randomly "
    "generated during the NFT minting using the Chainlink VRF oracle smart contract. "
    "Thus, each playing board generated is truly random and may not be determined ahead of time. "

    "Each NFT contains three playing boards: a 5x5, 7x7 and 9x9 playing board. The middle square "
    "in each playing board is a free square. For a ConnectX player to win, either their 5x5, "
    "7x7, or 9x9 playing board must contain a matching row, column, or diagonal of values. "

    "The values in each square of a playing board represent owners of randomly selected "
    "Collect9 physically redeemable NFTs (C9Ts). As C9T owners may change via exchange, "
    "that means each playing board is temporally dynamic. This also means owners of the "
    "playing boards also have some control in trying to form matching rows, columns, or "
    "diagonals by pursuing the specific C9Ts assigned to their squares. "

    "Long-term, as C9T NFTs are redeemed, some squares may become static as redeemed C9Ts may "
    "no longer change owner address. They may also be burned by the redeemer, which would effectively "
    "scramble all existing playing boards. Such a mechanism is permitted to mitigate the advantage of "
    "progressed playing boards versus those newly minted. "

    "Along with the token prize pot, winners will have their playing board converted to a trophy style "
    "golden board with their winner number and winning public address forever engraved on the board. "
    "Winners boards remain tradeable but are no longer playable."
    
    "When a winner is determined, the playing round completes and all previously minted boards are "
    "marked as expired making them no longer playable or tradeable. They may however be reactivated "
    "putting them back into play, as opposed to minting new replacement boards. Boards may only remain "
    "expired for a threshold number of rounds before they become permanently expired. "
    "Such a mechanism will prevent users from progressing on expired game boards before reactivating them. "

    "NFTs with active game boards are otherwise free to be exchanged through EIP-2981 or other royalties "
    "supporting marketplaces. ";

    address public immutable contractGame;
    constructor(address _contractGame) {
        contractGame = _contractGame;
    }

    /**
     * @dev Constructs the json string portion containing the external_url, description, 
     * and name parts.
     */
    function metaNameDesc(uint256 tokenId)
        external pure override
        returns(bytes memory) {
            bytes6 _id = Helpers.tokenIdToBytes(tokenId);
            bytes memory _datap1 = '{'
                '"external_url":"https://collect9.io/connectX",'
                '"name":"Collect9 ConnectX NFT #      ",'
                '"description":';
            assembly {
                let dst := add(_datap1, 110)
                mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
            }
            return bytes.concat(
                _datap1,
                DESC,
                '"}'
            );
    }

    function metaAttributes(uint256 tokenId, uint256 threshold)
    external view
    returns (bytes memory b) {
        uint256 currentRoundId = IC9Game(contractGame).currentRoundId();
        (,uint256 tokenRoundId,) = IC9Game(contractGame).tokenData(tokenId);
        (address _priorWinner,,) = IC9Game(contractGame).priorWinnerData(tokenId);

        bytes3 expired = tokenRoundId < currentRoundId ? bytes3("YES") : bytes3("NO ");
        bytes3 priorWinner = _priorWinner == address(0) ? bytes3("NO ") : bytes3("YES");
        bytes3 locked = bytes3("NO ");
        if ((currentRoundId - tokenRoundId) > threshold) {
            locked = "YES";
        }

        b = '","attributes":['
            '{"trait_type":"Expired","value":"   "},'
            '{"trait_type":"Locked","value":"   "},'
            '{"trait_type":"Prior Winner","value":"   "}'
            ']}';
        assembly {
            let dst := add(b, 81)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), expired))
            dst := add(b, 119)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), locked))
            dst := add(b, 163)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), priorWinner))
        }
    }
}