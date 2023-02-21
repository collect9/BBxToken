// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// Winning Board is forever locked
// Expired boards can be reactivated for a higher buy-in fee
// Buy-in fee increases with time

import "./utils/Helpers.sol";
import "./utils/C9ERC721Base.sol";
//import "./utils/C9ERC721BaseEnum.sol";
import "./utils/C9VRF3.sol";

import "./interfaces/IC9Game.sol";
import "./interfaces/IC9GameSVG.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";
import "./abstract/C9Errors.sol";

uint256 constant MAX_MINT_BATCH_SIZE = 50;

contract C9Game is IC9Game, C9ERC721, C9RandomSeed {
    /*
    _owners Non-Enumerable:
    0-160: owner
    176-192: roundID (u16)
    192-256: randomSeed (u64)

    _owners Enumerable:
    0-160: owner
    160-176: owned token index (u16)
    176-192: roundID (u16)
    192-256: randomSeed (u64)
    */
    struct MintAddressPool {
        address to;
        uint8 N;
    }

    // Tracking of contract balance with fees
    uint256 private _balance;
    uint256 private _c9Fees;
    uint256 private _mintingFee;
    uint256 private _c9PortionFee;

    // Current round parameters
    uint256 private _roundId;
    uint256 private _modulus;

    // Connecting contracts
    address private contractPricer;
    address private contractSVG;
    address private immutable contractToken;

    // Payout fractions
    uint48[2] private _payoutSplit;
    mapping(uint256 => uint256) private _payoutTiers;

    // Event for winner owns the C9Ts
    event Winner(
        address indexed winner,
        uint256 indexed tokenId,
        uint256 indexed winnings
    );

    // Event for winner does not own the C9Ts
    event WinnerSplit(
        address indexed winner,
        uint256 indexed tokenId,
        uint256 indexed winnings
    );

    /*
     * Network: Mainnet
     * VRF: 
     * Network: Sepolia
     * VRF: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     *
     * A lot of variables since a sustainable fee structure 
     * isn't known at deployment.
     */
    constructor(
        address _contractToken,
        address _contractPriceFeed,
        address _vrfCoordinator
        )
        C9ERC721("Collect9 ConnectX NFT", "C9X")
        C9RandomSeed(_vrfCoordinator)
    {
        // Fee params
        _mintingFee = 5;
        _c9PortionFee = 25;
        _payoutSplit = [uint48(25), 75];
        _payoutTiers[5] = 40;
        _payoutTiers[7] = 70;
        _payoutTiers[9] = 100;
        
        // Round params
        _roundId = 1;
        _modulus = IC9Token(_contractToken).totalSupply();
        
        // Linked contracts
        contractPricer = _contractPriceFeed;
        contractToken = _contractToken;
    }

    modifier validGameSize(uint256 _gameSize) {
        if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                revert GameSizeError(_gameSize);
        }
        _;
    }

    modifier validRoundId(uint256 tokenId) {
        uint256 _tokenRoundId = uint256(uint8(_owners[tokenId]>>POS_ROUND_ID));
        if (_tokenRoundId < _roundId) {
            revert ExpiredToken(tokenId, _tokenRoundId, _roundId);
        }
        _;
    }

    /**
     * @dev Required overrides from imported contracts.
     * This one checks to make sure the token is not locked 
     * due to being expired or that the contract is not 
     * frozen.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
        notFrozen()
        validRoundId(tokenId) {
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /*
     * @dev This is a batch function that
     * sets the game boards for the last N tokens minted.
     * _tokenCounter, a state variable, is the last tokenID 
     * minted. It, along with _seed are copied to memory to 
     * nreduce gas costs in the loop.
     */
    function _setTokenGameBoards(uint256 _tokenId, uint256 N, uint256 _randomSeed)
        private {
            uint256 _packedToken;
            uint256 _currentRoundId = _roundId;
            uint256 _tokenIdMax = _tokenId+N;
            for (_tokenId; _tokenId<_tokenIdMax;) {
                _packedToken = _owners[_tokenId];
                _packedToken |= _currentRoundId<<POS_ROUND_ID;
                _packedToken |= _randomSeed<<POS_SEED;
                _owners[_tokenId] = _packedToken;
                /*
                Unchecked because don't care if _randomSeed overflows 
                and warps around since it is still random and useful.
                */
                unchecked {
                    _randomSeed += uint256(
                        keccak256(
                            abi.encodePacked(
                                _randomSeed
                            )
                        )
                    );
                    ++_tokenId;
                }
            }
    }

    /*
     * @dev Returns contract balances.
     */
    function balances()
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns(uint256 balance, uint256 c9Balance, uint256 c9Fees) {
            balance = address(this).balance;
            c9Balance = _balance;
            c9Fees = _c9Fees;
    }

    // Indices supplied from front end. The reason is in case multiple valid 
    // rows are present, the winner can manually choose the row.
    // Maybe add non-entrancy guard for this
    function checkWinner(uint256 tokenId, uint256[] calldata indices)
        external {
            // Validate token exists
            if (!_exists(tokenId)) {
                revert InvalidToken(tokenId);
            }
            // Validate msg.sender is owner
            if (ownerOf(tokenId) != msg.sender) {
                revert CallerNotOwnerOrApproved();
            }
            // Validate the tokenId
            uint256 _tokenRoundId = uint256(uint16(_owners[tokenId]>>POS_ROUND_ID));
            if (_tokenRoundId < _roundId) {
                revert ExpiredToken(tokenId, _tokenRoundId, _roundId);
            }
            // Validate the gameSize
            uint256 _gameSize = indices.length;
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                revert GameSizeError(_gameSize);
            }
            // Validate the indices are a row, col, or diag
            uint256[] memory _sortedIndices = Helpers.quickSort(indices);
            if (!validIndices(_sortedIndices)) {
                revert InvalidIndices();
            }
            // Get the C9T tokenIds from the gameboard
            uint256[] memory _c9TokenIds = viewIndicesTokenIds(tokenId, _sortedIndices);
            // Validate all owners of c9TokenIds match
            uint256 middleIdx = (_gameSize*_gameSize)/2;
            address _tokenOwner = IC9Token(contractToken).ownerOf(_c9TokenIds[0]);
            for (uint256 i=1; i<_gameSize;) {
                if (IC9Token(contractToken).ownerOf(_c9TokenIds[i]) != _tokenOwner) {
                    if (_sortedIndices[i] != middleIdx) {
                        revert NotAWinner(tokenId);
                    }
                }
                unchecked {++i;}
            }

            // If we make it here, we have a winner!

            // 1. Get the payout balance
            (uint256 split0, uint256 split1) = currentPotSplit(_gameSize);
            uint256 _winningPayoutsFull = split0 + split1;
            
            // 2. Update the remaining balances/pot for the next round.
            _balance -= _winningPayoutsFull;

            // 3. Set the contract params for next round
            unchecked {++_roundId;}
            _modulus = IC9Token(contractToken).totalSupply();

            // 4. Freeze contract (will be unfrozen to start next round)
            _frozen = true;
            
            // 5. Process payout
            if (msg.sender == _tokenOwner) {
                // 5a. Payout 100% of _winningPayoutsFull to msg.sender
                (bool success,) = payable(msg.sender).call{value: _winningPayoutsFull}("");
                if(!success) {
                    revert PaymentFailure(address(this), msg.sender, _winningPayoutsFull);
                }
                emit Winner(msg.sender, tokenId, _winningPayoutsFull);
            }
            else {
                // 5b. Payout (75%, 25%) of _winningPayoutsFull to (msg.sender, _tokenOwner)
                (bool success,) = payable(msg.sender).call{value: split1}("");
                if(!success) {
                    revert SplitPaymentFailure(
                        address(this),
                        msg.sender,
                        split1
                    );
                }
                (success,) = payable(_tokenOwner).call{value: split0}("");
                if(!success) {
                    revert SplitPaymentFailure(
                        address(this),
                        _tokenOwner,
                        split0
                    );
                }
                emit WinnerSplit(msg.sender, tokenId, split1);
                emit WinnerSplit(_tokenOwner, tokenId, split0);
            }
    }

    /**
     * @dev Returns the current game pot in Wei.
     * This is the full winning for when the winner 
     * also owns the C9T NFTs that formed the winning array.
     */
    function currentPot(uint256 _gameSize)
        public view override
        returns(uint256) {
            return _balance*_payoutTiers[_gameSize]/100;
    }

    /**
     * @dev Returns split-win information.
     * This is the winning when the winner does not 
     * own the C9Ts that formed the winning array. The winner 
     * gets payout[1] and the owner of the C9Ts that formed the 
     * winning arrays gets payout[0].
     * The sum of the return is the full winning for when the winner 
     * also owns the C9T NFTs that formed the winning array.
     */
    function currentPotSplit(uint256 _gameSize)
        public view
        returns(uint256 payout0, uint256 payout1) {
            uint256 _winningPayouts = currentPot(_gameSize);
            payout0 = _payoutSplit[0]*_winningPayouts/100;
            payout1 = _payoutSplit[1]*_winningPayouts/100;
    }

    /**
     * @dev The minimum tokenID that is valid for the current 
     * playing round. All tokenIDs that are less than this tokenID 
     * are no longer valid / expired, and are locked to the holder's 
     * account to prevent users from trying to sell expired game boards. 
     */
    function currentRoundId()
        external view
        override
        returns (uint256) {
            return _roundId;
    }

    /**
     * @dev Returns split-win information.
     * Deposit function if needed for the next round in case the last winner 
     * is of a 9x9 board that cleans out the pot.
     */
    function deposit()
        external payable
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _balance += msg.value;
    }

    /**
     * @dev Second part of the minting.
     * Once the random number request has been fulfilled, the 
     * contract will mint the NFTs to the requester, who has 
     * already paid the minting fee.
     * Potential problem here if VRF fulfills recent before older.
     * Fix: harcode the round ID into the gameBoard and base expiry on that.
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords)
        internal override {
            super.fulfillRandomWords(_requestId, _randomWords);
            uint256 _statusRequest = statusRequests[_requestId];
            uint256 tokenId = uint256(uint24(_statusRequest));
            uint256 N = uint256(uint8(_statusRequest>>24));
            _setTokenGameBoards(tokenId, N, _randomWords[0]);
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(address pricerContract, address svgContract, address tokenContract) {
            pricerContract = contractPricer;
            svgContract = contractSVG;
            tokenContract = contractToken;
    }

    /**
     * @dev Returns the minting fee for N tokens in Wei.
     */
    function getMintingFee(uint256 N)
        public view
        returns (uint256) {
            return IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_mintingFee*N);
    }

    function mint(uint256 N)
        external payable
        notFrozen() {
            if (N > 0) {
                if (N > MAX_MINT_BATCH_SIZE) {
                    revert BatchSizeTooLarge(MAX_MINT_BATCH_SIZE, N);
                }
                uint256 mintingFeeWei = getMintingFee(N);
                if (msg.value != mintingFeeWei) {
                    revert InvalidPaymentAmount(mintingFeeWei, msg.value);
                }
                _balance += ((100-_c9PortionFee)*msg.value/100);
                _c9Fees += (_c9PortionFee*msg.value/100);
                requestRandomWords(msg.sender, _tokenCounter, N);
                _safeMint(msg.sender, N);
            }
            else {
                revert ZeroMintError();
            }
    }

    function mintPool(MintAddressPool[] calldata addressPool)
        external payable
        notFrozen() {
            uint256 _poolSize = addressPool.length;
            uint256 N;
            for (uint256 i; i<_poolSize;) {
                N += addressPool[i].N;
                unchecked {++i;}
            }

            if (N > 0) {
                if (N > MAX_MINT_BATCH_SIZE) {
                    revert BatchSizeTooLarge(MAX_MINT_BATCH_SIZE, N);
                }
                uint256 mintingFeeWei = getMintingFee(N);
                if (msg.value != mintingFeeWei) {
                    revert InvalidPaymentAmount(mintingFeeWei, msg.value);
                }
                _balance += ((100-_c9PortionFee)*msg.value/100);
                _c9Fees += (_c9PortionFee*msg.value/100);
                requestRandomWords(msg.sender, _tokenCounter, N);
                for (uint256 i; i<_poolSize;) {
                    _safeMint(addressPool[i].to, addressPool[i].N);
                    unchecked {++i;}
                }
            }
            else {
                revert ZeroMintError();
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

    /**
     * @dev Sets the SVG display contract address.
     */
    function setContractSVG(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            contractSVG = _address;
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

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in hmtl/xml code.
     */
    function svgImage(uint256 tokenId, uint256 gameSize)
        external view
        returns (string memory) {
            if (_exists(tokenId)) {
                return IC9GameSVG(contractSVG).svgImage(tokenId, gameSize);
            }
            else {
                return "";
            }
    }

    function tokenRoundId(uint256 tokenId)
        external view
        returns (uint256) {
            return uint256(uint16(_owners[tokenId]>>POS_ROUND_ID));
    }


    /**
     * @dev View function to see the numbers generated 
     * in the game board. This is essentially the base 
     * of the playing board.
     */
    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
        external view
        override
        validGameSize(_gameSize)
        returns (uint256[] memory) {
            uint256 _boardSize = _gameSize*_gameSize;
            uint256 _randomExpanded = uint256(
                keccak256(
                    abi.encodePacked(uint64(_owners[tokenId]>>POS_SEED))
                )
            );
            uint256 __modulus = _modulus;
            uint256[] memory _c9TokenIdEnums = new uint256[](_boardSize);
            for (uint256 i; i<_boardSize;) {
                unchecked {
                    _c9TokenIdEnums[i] = uint256(_randomExpanded>>i) % __modulus;
                    ++i;
                }
            }
            return _c9TokenIdEnums;
    }

    /*
     * @dev View function to convert indices of the game board into C9T tokenIds.
     */
    function viewIndicesTokenIds(uint256 tokenId, uint256[] memory _sortedIndices)
        public view
        returns (uint256[] memory) {
            uint256 _gameSize = _sortedIndices.length;
            uint256 _randomExpanded = uint256(
                keccak256(
                    abi.encodePacked(_owners[tokenId]>>POS_SEED)
                )
            );
            uint256 __modulus = _modulus;
            uint256 _c9EnumIndex;
            uint256[] memory _c9TokenIdEnums = new uint256[](_gameSize);
            for (uint256 i; i<_gameSize;) {
                unchecked {
                    _c9EnumIndex = uint256(_randomExpanded>>_sortedIndices[i]) % __modulus;
                    _c9TokenIdEnums[i] = IC9Token(contractToken).tokenByIndex(_c9EnumIndex);
                    ++i;
                }
            }
            return _c9TokenIdEnums;
    }

    function validIndices(uint256[] memory _sortedIndices)
        public pure 
        returns (bool) {
            uint256 _gameSize = _sortedIndices.length;
            uint256 _loopSize = _gameSize-1;
            uint256 index0 = _sortedIndices[0];

            // 1. Check if the arrangement is a valid column
            if (index0 < _gameSize) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _gameSize) {
                        break;
                    }
                    unchecked {--i;}
                    if (i == 0) {
                        return true;
                    }
                }
            }

            // 2. Check if the arrangement is a valid row
            if (index0 % _gameSize == 0) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != 1) {
                        break;
                    }
                    unchecked {--i;}
                    if (i == 0) {
                        return true;
                    }
                }
            }

            // 3. Check if the arrangement is a valid lower diag
            uint256 _lDx = _gameSize + 1;
            if (index0 == 0) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _lDx) {
                        break;
                    }
                    unchecked {--i;}
                    if (i == 0) {
                        return true;
                    }
                }
            }

            // 4. Check if the arrangement is a valid upper diag
            _lDx = _gameSize - 1;
            if (index0 == _gameSize-1) {
                for (uint256 i=_loopSize; i>0;) {
                    if (_sortedIndices[i] - _sortedIndices[i-1] != _lDx) {
                        break;
                    }
                    unchecked {--i;}
                    if (i == 0) {
                        return true;
                    }
                }
            }

            // 5. No valid arrangements found
            return false;
    }

    /*
     * @dev Removes the full balance.
     * This is only to be used as a fail-safe incase the 
     * contract isn't functional, so funds do not get
     * stuck and thus lost.
     */
    function withdraw(uint256 amount, bool confirm)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (confirm) {
                if (amount == 0) {
                    payable(owner).transfer(address(this).balance);
                    _balance = 0;
                }
                else {
                    payable(owner).transfer(amount);
                    _balance -= amount;
                }
            }
            else {
                revert ActionNotConfirmed();
            }
    }

    /*
     * @dev Removes the fee balance that accumulates 
     * after the completion of rounds.
     */
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