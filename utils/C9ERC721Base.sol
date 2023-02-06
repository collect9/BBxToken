// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./utils/C9ERC721Base.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

address constant TOKEN_CONTRACT = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
uint256 constant GAME_SIZE = 25;
uint256 constant MODULUS = 272;

contract C9Game is ERC721 {

    mapping(uint256 => uint256) private _tokenIdBoard;
    uint256 private _seed; //Use contract pricer
    uint256 private _minTokenId;
    address private contractPricer;
    address private immutable contractToken;

    constructor(address _contractToken)
        ERC721("Collect9 NFT Game Connect9", "C9X") {
            contractToken = _contractToken;
    }

    function mint(uint256 N) 
        external payable {
            _mint(msg.sender, N);
            uint256 _randomNumber;
            uint256 _tokenIndex = _tokenId-1;
            for (uint i; i<N;) {
                unchecked {
                    _randomNumber = uint256(
                        keccak256(
                            abi.encodePacked(
                                block.prevrandao,
                                msg.sender,
                                _seed
                            )
                        )
                    );
                    _seed += _randomNumber;
                    _owners[_tokenIndex] = _setTokenParam(
                        _owners[_tokenIndex],
                        160,
                        _randomNumber,
                        type(uint96).max
                    );
                    --_tokenIndex;
                    ++i;
                }
            }
    }

    function totalSupply()
        external view
        returns (uint256) {
            return _tokenId;
    }

    function viewBoard(uint256 tokenId, uint256 size)
        public view
        returns (uint256[] memory) {
            //require size = 5,7,9
            uint256 _gameSize = size*size;
            uint256[] memory _gameBoard = new uint256[](_gameSize);
            uint256 _packedNumers = _owners[tokenId];
            uint256 _offset = 160;
            for (uint i; i<_gameSize;) {
                unchecked {
                    _gameBoard[i] = uint256(_packedNumers>>_offset) % MODULUS;
                    ++_offset;
                    ++i;
                }
            }
            return _gameBoard;
    }

    // Fastest/cheapest way is to have the indices to check for a win already supplied
    function checkWinner(uint256 tokenId, uint256[] calldata indices)
        external view {
            uint256 _gameSize = indices.length;
            //require _gameSize = 5,7,9
            uint256[] memory _gameBoard = viewBoard(tokenId, _gameSize);
            address _tokenOwner = IC9Token(contractToken).ownerOf(_gameBoard[0]);
            for (uint i=1; i<_gameSize;) {
                if (IC9Token(contractToken).ownerOf(_gameBoard[0]) != _tokenOwner) {
                    //revert not a winner 
                }
                unchecked {++i;}
            }
            // If we make it here, we have a winner

            /*
            If msg.sender == _tokenOwner, payout full 90% to msg.sender
            Else payout 65% to msg.sender, 25% to _tokenOwner

            Payout 5% to Collect9
            Roll remainder (5%) into next round
            */

    }

    function win()
        private {
            _minTokenId = _tokenId;
    }
}