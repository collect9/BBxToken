// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./utils/Helpers.sol";
import "./utils/C9ERC721Base.sol";
import "./utils/C9VRF3.sol";

import "./interfaces/IC9Game.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";
import "./abstract/C9Errors.sol";

contract C9Game is IC9Game, ERC721, C9RandomSeed {
    // Tracking of contract balance with fees
    uint256 private _balance;
    uint256 private _c9Fees;
    uint256 private _mintingFee;

    // Current round parameters
    uint256 private _minTokenId;
    uint256 private _modulus;

    // Connecting contracts
    address private contractPricer;
    address private immutable contractToken;

    // Payout fractions
    uint48[2] private _payoutSplit;
    mapping(uint256 => uint256) private _payoutTiers;

    // Event for winner owns the C9Ts
    event Winner1(
        address indexed winner,
        uint256 indexed tokenId,
        uint256 indexed winnings
    );

    // Event for winner does not own the C9Ts
    event Winner2(
        address indexed winner,
        address indexed tokenOwner,
        uint256 indexed winnings
    );

    /*
     * Network: Mainnet
     * VRF: 
     * Network: Sepolia
     * VRF: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
    */
    constructor(
        address _contractToken,
        address _contractPriceFeed,
        address _vrfCoordinator
        )
        ERC721("Collect9 NFT Bingo", "C9X")
        C9RandomSeed(_vrfCoordinator)
    {
        _mintingFee = 5;
        _payoutSplit = [uint48(25), 75];
        _payoutTiers[5] = 33;
        _payoutTiers[7] = 67;
        _payoutTiers[9] = 100;
        _modulus = IC9Token(_contractToken).totalSupply();
        contractPricer = _contractPriceFeed;
        contractToken = _contractToken;
    }

    /*
     * @dev This is a batch function that
     * sets the game boards for the last N tokens minted.
     * _tokenCounter, a state variable, is the last tokenID 
     * minted. It, along with _seed are copied to memory to 
     * nreduce gas costs in the loop.
     */
    function _setTokenGameBoard(uint256 N, uint256 _randomMintSeed)
        private {
            uint256 _tokenIdMax = _tokenCounter;
            uint256 _tokenId = _tokenIdMax-N;
            for (_tokenId; _tokenId<_tokenIdMax;) {
                unchecked {
                    _owners[_tokenId] = _setTokenParam(
                        _owners[_tokenId],
                        160,
                        _randomMintSeed,
                        type(uint96).max
                    );
                    _randomMintSeed += uint256(
                        keccak256(
                            abi.encodePacked(
                                block.prevrandao,
                                msg.sender,
                                _randomMintSeed
                            )
                        )
                    );
                    ++_tokenId;
                }
            }
    }

    function balances()
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns(uint256 balance, uint256 c9WeiBalance, uint256 c9WeiFees) {
            balance = address(this).balance;
            c9WeiBalance = _balance;
            c9WeiFees = _c9Fees;
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
            uint256[] memory _sortedIndices = Helpers.quickSort(indices);
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
            _frozen = true;            
    }

    function currentPots(uint256 _gameSize)
        external view
        returns(uint256[2] memory splitPayouts) {
            uint256 winningPayouts = 90*_balance*_payoutTiers[_gameSize]/1000000;
            splitPayouts[0] = _payoutSplit[0]*winningPayouts;
            splitPayouts[1] = _payoutSplit[1]*winningPayouts;
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords)
        internal override {
            super.fulfillRandomWords(_requestId, _randomWords);
            uint256 N = statusRequests[_requestId].numberOfMints;
            _safeMint(statusRequests[_requestId].requester, N);
            _setTokenGameBoard(N, _randomWords[0]);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(address pricerContract, address tokenContract) {
            pricerContract = contractPricer;
            tokenContract = contractToken;
    }

    function getMintingFee(uint256 N)
        public view
        returns (uint256) {
            return IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_mintingFee*N);
    }

    function minRoundTokenId()
        external view
        override
        returns (uint256) {
            return _minTokenId;
    }

    function mint(uint256 N)
        external payable
        onlyRole(DEFAULT_ADMIN_ROLE) 
        notFrozen() {
            if (N > 0) {
                uint256 mintingFeeWei = getMintingFee(N);
                if (msg.value != mintingFeeWei) {
                    //revert InvalidPaymentAmount(mintingFeeWei, msg.value);
                    revert("mint() InvalidPaymentAmount()");
                }
                _balance += msg.value;
                requestRandomWords(msg.sender, N);
            }
            else {
                revert("Cannot Mint 0");
            }
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractPricer == _address) {
                revert AddressAlreadySet();
            }
            contractPricer = _address;
    }

    function setMintingFee(uint256 fee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _mintingFee = fee;
    }

    function setPayoutSplit(uint256 winnerAmt, uint256 tokenOwnerAmt)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _payoutSplit = [uint48(winnerAmt), uint48(tokenOwnerAmt)];
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
            else {
                revert ActionNotConfirmed();
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
            else {
                revert ActionNotConfirmed();
            }
    }
}