// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./utils/C9ERC721Base.sol";
import "./interfaces/IC9Game.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";
import "./abstract/C9Errors.sol";

contract C9Game is IC9Game, ERC721 {

    mapping(uint256 => uint256) private _tokenIdBoard;
    uint256 public _seed; //Use contract pricer
    uint256 private _minTokenId;
    address public contractPricer;
    address public immutable contractToken;
    uint256 public _balance;
    uint256 public _c9Fees;
    uint256 public _modulus;

    uint128[2] private _payoutSplit;
    mapping(uint256 => uint256) private _payoutTiers;

    event Winner1(
        address indexed winner,
        uint256 indexed tokenId,
        uint256 indexed winnings
    );

    event Winner2(
        address indexed winner,
        address indexed tokenOwner,
        uint256 indexed winnings
    );

    constructor(address _contractToken)
        ERC721("Collect9 NFT Bingo ConnectX", "C9X") {
            contractToken = _contractToken;
            _modulus = IC9Token(contractToken).totalSupply();
            _payoutSplit[0] = 25;
            _payoutSplit[1] = 75;
            _payoutTiers[5] = 33;
            _payoutTiers[7] = 67;
            _payoutTiers[9] = 100;
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

    function _quickSort(uint256[] calldata data)
        private pure 
        returns (uint256[] memory sorted) {
            sorted = data;
            if (sorted.length > 1) {
                _quick(sorted, 0, sorted.length - 1);
            }
    }

    function _setTokenGameBoard(uint256 N)
        private {
            uint256 _randomNumber;
            uint256 _tokenIdMax = _tokenCounter;
            uint256 _tokenId = _tokenIdMax-N;
            uint256 __seed = _seed;
            for (_tokenId; _tokenId<_tokenIdMax;) {
                unchecked {
                    _randomNumber = uint256(
                        keccak256(
                            abi.encodePacked(
                                block.prevrandao,
                                msg.sender,
                                __seed
                            )
                        )
                    );
                    __seed += _randomNumber;
                    _owners[_tokenId] = _setTokenParam(
                        _owners[_tokenId],
                        160,
                        _randomNumber,
                        type(uint96).max
                    );
                    ++_tokenId;
                }
            }
            _seed = __seed;
    }

    function balances()
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns(uint256, uint256, uint256) {
            return (address(this).balance, _balance, _c9Fees);
    }

    // Indices supplied from front end. The reason is in case multiple valid 
    // rows are present, the winner can manually choose the row.
    function checkWinner(uint256 tokenId, uint256[] calldata indices)
        external {
            // Validate token exists
            if (!_exists(tokenId)) {
                revert("checkWinner() InvalidToken(tokenId)");
            }
            // Validate msg.sender is owner
            if (ownerOf(tokenId) != msg.sender) {
                revert("checkWinner() CallerNotOwnerOrApproved");
            }
            // Validate the tokenId
            if (tokenId < _minTokenId) {
                //revert ExpiredToken(_minTokenId, tokenId);
                revert("checkWinner() ExpiredToken");
            }
            // Validate the gameSize
            uint256 _gameSize = indices.length;
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                //revert GameSizeError(_gameSize);
                revert("checkWinner() GameSizeError");
            }
            // Validate the indices are a row, col, or diag
            uint256[] memory _sortedIndices = _quickSort(indices);
            if (!validIndices(_sortedIndices)) {
                //revert InvalidIndices();
                revert("checkWinner() InvalidIndices");
            }
            // Get the C9T tokenIds from the gameboard
            uint256[] memory _c9TokenIds = viewIndicesTokenIds(tokenId, _sortedIndices);
            // Validate all owners of c9TokenIds match
            uint256 middleIdx = (_gameSize*_gameSize)/2;
            address _tokenOwner = IC9Token(contractToken).ownerOf(_c9TokenIds[0]);
            for (uint256 i=1; i<_gameSize;) {
                if (IC9Token(contractToken).ownerOf(_c9TokenIds[i]) != _tokenOwner) {
                    if (_sortedIndices[i] != middleIdx) {
                        //revert NotAWinner(tokenId);
                        revert("checkWinner() NotAWinner");
                    }
                }
                unchecked {++i;}
            }

            // If we make it here, we have a winner
            uint256 _winningPayouts = 90*_balance*_payoutTiers[_gameSize]/10000;
            uint256 _c9Fee = 5*_balance/100;
            // New _balance will be 5% of the original _balance
            _balance -= (_winningPayouts + _c9Fee);
            _c9Fees += _c9Fee;
            
            if (msg.sender == _tokenOwner) {
                // Payout full winnings to msg.sender
                (bool success,) = payable(msg.sender).call{value: _winningPayouts}("");
                if(!success) {
                    //revert PaymentFailure(address(this), msg.sender, _winningPayouts);
                    revert("checkWinner() PaymentFailure1");
                }
                emit Winner1(msg.sender, tokenId, _winningPayouts);
            }
            else {
                // Payout 75% of _winningPayouts to msg.sender
                uint256 _winning1Payouts =  _payoutSplit[1]*_winningPayouts/100;
                (bool success,) = payable(msg.sender).call{value: _winning1Payouts}("");
                if(!success) {
                    //revert PaymentFailure(address(this), msg.sender, _winning1Payouts);
                    revert("checkWinner() PaymentFailure2");
                }
                // Payout 25% of _winningPayouts to _tokenOwner
                uint256 _winning0Payouts =  _payoutSplit[0]*_winningPayouts/100;
                (success,) = payable(_tokenOwner).call{value: _winning0Payouts}("");
                if(!success) {
                    //revert PaymentFailure(address(this), _tokenOwner, _winning0Payouts);
                    revert("checkWinner() PaymentFailure3");
                }
                emit Winner2(msg.sender, _tokenOwner, _winningPayouts);
            }
            
            // // Freeze contract token params for next round
            _minTokenId = _tokenCounter;
            _modulus = IC9Token(contractToken).totalSupply();
            unchecked {
                _seed += block.timestamp;
            }
            _frozen = true;            
    }

    function minRoundTokenId()
        external view
        override
        returns (uint256) {
            return _minTokenId;
    }

    function mint(uint256 N)
        external payable
        notFrozen() {
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

    function setPayoutSplit(uint128[2] calldata amounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _payoutSplit = amounts;
    }

    function setPayoutTier(uint256 tier, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _payoutTiers[tier] = amount;
    }

    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
        external view
        override
        returns (uint256[] memory) {
            // Validate the gameSize
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                //revert GameSizeError(_gameSize);
                revert("viewGameBoard() GameSizeError");
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
            uint256 _c9EnumIndex;
            for (uint256 i; i<_gameSize;) {
                unchecked {
                    _offset = 160 + _sortedIndices[i];
                    _c9EnumIndex = uint256(_packedNumers>>_offset) % __modulus;
                    _c9TokenIds[i] = IC9Token(contractToken).tokenByIndex(_c9EnumIndex);
                    ++i;
                }
            }
            return _c9TokenIds;
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

    function withdraw(bool confirm)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (confirm) {
                // Remove the full balance
                payable(owner).transfer(address(this).balance);
                _balance = 0;
                _c9Fees = 0;
            }        
    }

    function withdrawFees(bool confirm)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (confirm) {
                payable(owner).transfer(_c9Fees);
                _balance -= _c9Fees;
                _c9Fees = 0;
            }
    }
}