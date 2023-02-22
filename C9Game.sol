// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// Winning Board is forever locked - can enforce by setting tokenRoundId = 0
// Expired boards with non-zero tokenRoundId can be reactivated for a higher buy-in fee
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
    bool private _freezerEnabled = true;
    /*
    _owners Non-Enumerable:
    key: tokenId
    0-160: owner (u160)
    160-176: roundID (u16)
    176-256: randomSeed (u80)
    */
    mapping(uint256 => uint256) private _priorWinners;
    /*
    priorWinners
    key: tokenId
    0-160: winner (u160), since the prior won token can be traded around
    160-176: winnerNumber (u16)
    176-184: gameSize (u8)
    184-256: winningIndices (max u8x9)
    */

    // Struct for pool of minters
    struct MintAddressPool {
        address to;
        uint96 N;
    }

    // Tracking of contract balance with fees
    uint256 private _balance;
    uint256 private _c9Fees;
    uint256 private _mintingFee;
    uint256 private _c9PortionFee;

    // Current round parameters
    uint256 private _roundId;
    uint256 private _modulus;
    uint256 private _winnerCounter;

    // Connecting contracts
    address private contractPricer;
    address private contractSVG;
    address private immutable contractToken;

    // Payout fractions
    uint48[2] private _payoutSplit;
    mapping(uint256 => uint256) private _payoutTiers;

    // Event to emit upon win
    event Winner(
        address indexed winner1,
        address indexed winner2,
        uint256 indexed tokenId
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
        // Default fee params
        _mintingFee = 5;
        _c9PortionFee = 25;
        _payoutSplit = [uint48(25), 75];
        _payoutTiers[5] = 40;
        _payoutTiers[7] = 70;
        _payoutTiers[9] = 100;
        
        // Starting round params
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

    /**
     * @dev Required overrides from imported contracts.
     * This one checks to make sure the token is not locked 
     * due to being expired or that the contract is not 
     * frozen. Tokens that have won in the past may be
     * traded, but may not win again.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override
        notFrozen() {
            // 1. Get the token's saved roundId at mint 
            uint256 _tokenRoundId = uint256(uint16(_owners[tokenId]>>POS_ROUND_ID));
            // 2. Check if that roundId is expired
            if (_tokenRoundId < _roundId) {
                // 3. If expired but not a prior winning board, then revert
                if (_priorWinners[tokenId] == 0) {
                    revert ExpiredToken(tokenId, _tokenRoundId, _roundId);
                }
            }
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /*
     * @dev Sets the game board a single _tokenId.
     */
    function _setTokenGameBoard(uint256 _tokenId, uint256 _randomSeed)
        private {
            uint256 _packedToken = _owners[_tokenId];
            _packedToken |= _roundId<<POS_ROUND_ID;
            _packedToken |= _randomSeed<<POS_SEED;
            _owners[_tokenId] = _packedToken;
    }

    /*
     * @dev Sets the game boards for _tokenId plus 
     * any additional tokens as part of its minting batch.
     */
    function _setTokenGameBoards(uint256 _tokenId, uint256 N, uint256 _randomSeed)
        private {
            uint256 _tokenData;
            uint256 _tokenIdMax = _tokenId+N-1;
            uint256 _currentRoundId = _roundId; // Read from storage one time
            for (_tokenId; _tokenId<_tokenIdMax;) {
                _tokenData = _owners[_tokenId];
                _tokenData |= _currentRoundId<<POS_ROUND_ID;
                _tokenData |= _randomSeed<<POS_SEED;
                _owners[_tokenId] = _tokenData;
                /*
                Unchecked below because don't care if _randomSeed overflows 
                and warps around since it will still be random and useful.
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
            /*
            The last token is done outside of the loop to avoid doing an additional 
            and unnecessary _randomSeed += operation. This matters more the smaller 
            the batch sizes are. 
            */
            _tokenData = _owners[_tokenIdMax];
            _tokenData |= _currentRoundId<<POS_ROUND_ID;
            _tokenData |= _randomSeed<<POS_SEED;
            _owners[_tokenIdMax] = _tokenData;
    }

    /*
     * @dev Store data for the winners. The data is used 
     * for display purposes as well as enforced allowing 
     * exchange of prior won tokens.
     */
    function _storeWinner(uint256 tokenId, address winner, uint256 _gameSize, uint256[] memory _sortedIndices)
        private {
            // 1. Increment winner count
            unchecked {++_winnerCounter;} 
            // 2. Create winning data
            uint256 _winnerData;
            _winnerData |= uint256(uint160(winner));
            _winnerData |= _winnerCounter<<WPOS_WINNING_ID;
            _winnerData |= _gameSize<<WPOS_GAMESIZE;
            uint256 _offset = WPOS_INDICES;
            for (uint256 i; i<_gameSize;) {
                _winnerData |= _sortedIndices[i]<<_offset;
                unchecked {_offset += 8;}
            }
            // 3. Store winning data
            _priorWinners[tokenId] = _winnerData;
    }

    /*
     * @dev Returns contract balances. The balance is returned 
     * as well for quick ease of comparison to make sure the 
     * other two balances are tracking properly.
     */
    function balances()
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns(uint256 balance, uint256 c9Balance, uint256 c9Fees) {
            balance = address(this).balance;
            c9Balance = _balance;
            c9Fees = _c9Fees;
    }

    /*
     * @dev Function to check if the tokenId is a winner. 
     * A series of checks are done to ensure the token is valid.
     */
    function checkWinner(uint256 tokenId, uint256[] calldata indices)
        external {
            // V1. Validate tokenId exists
            if (!_exists(tokenId)) {
                revert InvalidToken(tokenId);
            }
            // V2. If it exists, validate the msg.sender is the tokenId owner
            if (ownerOf(tokenId) != msg.sender) {
                revert CallerNotOwnerOrApproved();
            }
            // V3. Validate the tokenId is not expired
            uint256 _tokenData = _owners[tokenId];
            uint256 _tokenRoundId = uint256(uint16(_tokenData>>POS_ROUND_ID));
            if (_tokenRoundId < _roundId) {
                revert ExpiredToken(tokenId, _tokenRoundId, _roundId);
            }
            // V4. Validate the gameSize based on calldata indices length
            uint256 _gameSize = indices.length;
            if (_gameSize != 5 && _gameSize != 7 && _gameSize != 9) {
                revert GameSizeError(_gameSize);
            }
            // V5. Validate calldata indices are a valid row, column, or diagnol
            uint256[] memory _sortedIndices = Helpers.quickSort(indices);
            if (!validIndices(_sortedIndices)) {
                revert InvalidIndices();
            }

            // All checks have passed up to this point!

            // C1. Get the C9T tokenIds from calldata indices
            uint256[] memory _c9TokenIds = viewIndicesTokenIds(tokenId, _sortedIndices);
            /*
            C2. To check if we have a winner, the ownerOf each _c9TokenIds 
            must match. Since the middle board index is free, it is ignored 
            if it shows up in the calldata indices.
            */
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

            // If make it here, we have a winner!!!

            // W1. Store winning data
            _storeWinner(tokenId, msg.sender, _gameSize, _sortedIndices);
            
            // W2. Get the payout amount based on winning _gameSize
            (uint256 split0, uint256 split1) = currentPotSplit(_gameSize);
            uint256 _winningPayoutsFull = split0 + split1;
            
            // W3. Update the balances and contract params for the next round
            _balance -= _winningPayoutsFull;
            _modulus = IC9Token(contractToken).totalSupply();
            unchecked {++_roundId;}

            /*
            W4: Freeze contract for the next around. The first few 
            are intended to be frozen to ensure the game is working 
            properly. After a while, the freezer can be disabled 
            so the next rounds start automatically.
            */
            if (_freezerEnabled) {
                _frozen = true;
            }
            
            /*
            W5. Process the payouts. If the owner of tokenId (msg.sender) 
            is the same as _tokenOwner of the winning indices, then the 
            owner of tokenId (msg.sender) will get both payouts since 
            msg.sender will equal _tokenOwner.
            */
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
            emit Winner(msg.sender, _tokenOwner, tokenId);
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
            if (N > 1) {
                _setTokenGameBoards(tokenId, N, _randomWords[0]);
            }
            else {
                _setTokenGameBoard(tokenId, _randomWords[0]);
            }
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

    function reactivate(uint256[] calldata tokenIds)
        external payable {
            uint256 N = tokenIds.length;
            if (N > 0) {
                uint256 _updatedRoundId = _roundId;
                uint256 reactivateFeeWei;
                for (uint256 i; i<N;) {
                    // Get last round Id, get fee from it
                    _owners[tokenIds[i]] = _setTokenParam(
                        _owners[tokenIds[i]],
                        POS_ROUND_ID,
                        _updatedRoundId,
                        type(uint16).max
                    );
                }
                if (msg.value != reactivateFeeWei) {
                    revert InvalidPaymentAmount(reactivateFeeWei, msg.value);
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

    function setFreezer(bool _val)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _freezerEnabled = _val;
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

    function tokenData(uint256 tokenId)
        external view override
        returns (address tokenOwner, uint256 tokenRoundId, uint256 randomSeed) {
            uint256 _tokenData = _owners[tokenId];
            tokenOwner = address(uint160(_tokenData));
            tokenRoundId = uint256(uint16(_tokenData>>POS_ROUND_ID));
            randomSeed = uint256(uint72(_tokenData>>POS_SEED));
    }

    function priorWinnerData(uint256 tokenId)
        external view
        returns (address priorWinner, uint256 winningNumber, uint256[] memory _indices) {
            uint256 _priorWinnerData = _priorWinners[tokenId];
            if (_priorWinnerData != 0) {
                priorWinner = address(uint160(_priorWinnerData));
                winningNumber = uint256(uint16(_priorWinnerData>>WPOS_WINNING_ID));
                uint256 _gameSize = uint256(uint8(_priorWinnerData>>WPOS_GAMESIZE));
                _indices = new uint256[](_gameSize);
                uint256 _offset = WPOS_INDICES;
                for (uint256 i; i<_gameSize;) {
                    _indices[i] = uint256(uint8(_priorWinnerData>>_offset));
                    unchecked {
                        ++i;
                        _offset += 8;
                    }
                }
            }
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