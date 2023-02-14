// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./utils/C9ERC721Base.sol";
import "./interfaces/IC9Game.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";
import "./abstract/C9Errors.sol";

contract C9Game is IC9Game, ERC721 {

    mapping(uint256 => uint256) private _tokenIdBoard;
    uint256 private _seed; //Use contract pricer
    uint256 private _minTokenId;
    address private contractPricer;
    address private immutable contractToken;
    uint256 private _balance;
    uint256 private _c9Fees;
    uint256 private _modulus;

    constructor(address _contractToken)
        ERC721("Collect9 NFT Game Connect9", "C9X") {
            contractToken = _contractToken;
            _modulus = IC9Token(contractToken).totalSupply();
    }

    function _setTokenGameBoard(uint256 N)
        private {
            uint256 _randomNumber;
            uint256 _tokenIndex = _tokenCounter-1;
            for (uint256 i; i<N;) {
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

    function mint(uint256 N)
        external payable {
        //notFrozen() {
            /*
            uint256 purchaseWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(5*N);
            if (msg.value != purchaseWeiPrice) {
                revert InvalidPaymentAmount(purchaseWeiPrice, msg.value);
            }
            */
            _balance += msg.value;
            _safeMint(msg.sender, N);
            _setTokenGameBoard(N);
    }

    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
        external view
        override
        returns (uint256[] memory) {
            // Validate the gameSize
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                revert GameSizeError(_gameSize);
            }
            uint256 _packedNumers = _owners[tokenId];
            uint256 _boardSize = _gameSize*_gameSize;
            uint256[] memory _c9TokenIds = new uint256[](_boardSize);
            uint256 _offset = 160;
            uint256 __modulus = _modulus;
            for (uint256 i; i<_boardSize;) {
                unchecked {
                    _c9TokenIds[i] = uint256(_packedNumers>>_offset) % __modulus;
                    ++i;
                    ++_offset;
                }
            }
            return _c9TokenIds;
    }

    function viewIndicesTokenIds(uint256 tokenId, uint256[] memory _sortedIndices)
        public view
        returns (uint256[] memory) {
            uint256 _gameSize = _sortedIndices.length;
            uint256[] memory _c9TokenIds = new uint256[](_gameSize);
            uint256 _packedNumers = _owners[tokenId];
            uint256 _offset;
            uint256 __modulus = _modulus;
            for (uint256 i; i<_gameSize;) {
                unchecked {
                    _offset = 160 + _sortedIndices[i];
                    _c9TokenIds[i] = uint256(_packedNumers>>_offset) % __modulus;
                    ++i;
                }
            }
            return _c9TokenIds;
    }

    // Indices supplied from front end. The reason is in case multiple valid 
    // rows are present, the winner can manually choose the row.
    function checkWinner(uint256 tokenId, uint256[] calldata indices)
        external {
            // Validate the tokenId
            if (tokenId < _minTokenId) {
                revert ExpiredToken(_minTokenId, tokenId);
            }
            // Validate the gameSize
            uint256 _gameSize = indices.length;
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                revert GameSizeError(_gameSize);
            }
            // Validate the indices are a row, col, or diag
            uint256[] memory _sortedIndices = quickSort(indices);
            if (!validIndices(_sortedIndices)) {
                revert InvalidIndices();
            }
            // Get the C9T tokenIds from the gameboard
            uint256[] memory _c9TokenIds = viewIndicesTokenIds(tokenId, _sortedIndices);
            // Validate all owners of c9TokenIds are a match
            address _tokenOwner = IC9Token(contractToken).ownerOf(_c9TokenIds[0]);
            for (uint256 i=1; i<_gameSize;) {
                if (IC9Token(contractToken).ownerOf(_c9TokenIds[i]) != _tokenOwner) {
                    revert NotAWinner(tokenId); 
                }
                unchecked {++i;}
            }

            // If we make it here, we have a winner
            uint256 _winningPayouts = 90*_balance/100;
            uint256 _c9Fee = 5*_balance/100;
            // New _balance will be 5% of the original _balance
            _balance -= (_winningPayouts + _c9Fee);
            _c9Fees += _c9Fee;
            
            if (msg.sender == _tokenOwner) {
                // Payout full winnings to msg.sender
                (bool success,) = payable(msg.sender).call{value: _winningPayouts}("");
                if(!success) {
                    revert PaymentFailure(address(this), msg.sender, _winningPayouts);
                }
            }
            else {
                // Payout 75% of _winningPayouts to msg.sender
                uint256 _winning75Payouts =  75*_winningPayouts/100;
                (bool success,) = payable(msg.sender).call{value: _winning75Payouts}("");
                if(!success) {
                    revert PaymentFailure(address(this), msg.sender, _winning75Payouts);
                }
                // Payout 25% of _winningPayouts to _tokenOwner
                uint256 _winning25Payouts =  25*_winningPayouts/100;
                (success,) = payable(_tokenOwner).call{value: _winning25Payouts}("");
                if(!success) {
                    revert PaymentFailure(address(this), _tokenOwner, _winning25Payouts);
                }
            }
            
            // Freeze contract token params for next round
            _minTokenId = _tokenCounter;
            _modulus = IC9Token(contractToken).totalSupply();
            //_frozen = true;
    }

    function quickSort(uint256[] calldata data)
        public pure 
        returns (uint256[] memory sorted) {
            sorted = data;
            if (sorted.length > 1) {
                _quick(sorted, 0, sorted.length - 1);
            }
    }

    function _quick(uint256[] memory data, uint256 low, uint256 high)
        private pure {
            if (low < high) {
                uint256 pivotVal = data[(low + high) / 2];
                uint256 low1 = low;
                uint256 high1 = high;

                for (;;) {
                    while (data[low1] < pivotVal) {
                        ++low1;
                    }
                    while (data[high1] > pivotVal) {
                        --high1;
                    }
                    if (low1 >= high1) {
                        break;
                    }
                    (data[low1], data[high1]) = (data[high1], data[low1]);
                    ++low1;
                    --high1;
                }
                if (low < high1) {
                    _quick(data, low, high1);
                }
                ++high1;
                if (high1 < high) {
                    _quick(data, high1, high);
                }
            }
    }

    function validIndices(uint256[] memory _sortedIndices)
        public pure 
        returns (bool) {
            uint256 _gameSize = _sortedIndices.length;
            uint256 _loopSize = _gameSize-1;
            uint256 index0 = _sortedIndices[0];
            // Check if a valid col
            if (index0 < _gameSize) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _gameSize) {
                        break;
                    }
                    unchecked {--i;}
                    if (i==0) {
                        return true;
                    }
                }
            }
            // Check if a valid row
            if (index0 % _gameSize == 0) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != 1) {
                        break;
                    }
                    unchecked {--i;}
                    if (i==0) {
                        return true;
                    }
                }
            }
            // Check if a valid lower diag
            uint256 _lDx = _gameSize + 1;
            if (index0 == 0) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _lDx) {
                        break;
                    }
                    unchecked {--i;}
                    if (i==0) {
                        return true;
                    }
                }
            }
            // Check if a valid upper diag
            _lDx = _gameSize - 1;
            if (index0 == _gameSize-1) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _lDx) {
                        break;
                    }
                    unchecked {--i;}
                    if (i==0) {
                        return true;
                    }
                }
            }
            return false; // Not a valid indices arrangement
    }

    // Withdraw only the C9Fees
    function withdraw(bool _all)
        external {
        //onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_all) {
                //payable(owner).transfer(address(this).balance);
            }
            else {
                //payable(owner).transfer(_c9Fees);
            }
    }
}