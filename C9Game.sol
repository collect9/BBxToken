// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// Winning Board is forever locked - can enforce by setting tokenRoundId = 0
// Expired boards with non-zero tokenRoundId can be reactivated for a higher buy-in fee
// Buy-in fee increases with time

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./utils/C9ERC721Base.sol";
import "./utils/C9VRF3.sol";

import "./interfaces/IC9Game.sol";
import "./interfaces/IC9GameMetaData.sol";
import "./interfaces/IC9GameSVG.sol";
import "./interfaces/IC9Token.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";
import "./abstract/C9Errors.sol";

uint256 constant MAX_MINT_BATCH_SIZE = 100;

contract C9Game is IC9Game, C9ERC721, C9RandomSeed {
    /*
    _owners Non-Enumerable:
    key: tokenId
    0-160: owner (u160)
    160-176: roundID (u16)
    176-256: randomSeed (u80)
    */
    bool private _freezerEnabled = true;
    struct MintAddressPool {
        address to;
        uint96 N;
    }

    mapping(uint256 => uint256) private _priorWinners;
    /*
    priorWinners
    key: tokenId
    0-160: winner (u160), since the prior won token can be traded around
    160-176: winnerNumber (u16)
    176-184: gameSize (u8)
    184-256: winningIndices (max u8x9)
    */

    /*
    Packing the state variables below isn't really worth it. 
    So they're sticking with mostly the solidity defaults.
    */
    // Tracking of contract balance with fees
    uint256 private _balance;
    uint256 private _c9Fees;
    uint256 private _mintingFee;
    uint256 private _c9PortionFee;

    // Current round parameters
    uint256 private _reactivationThreshold;
    uint256 private _roundId;
    uint256 private _modulus;
    uint256 private _winnerCounter;

    // Connecting contracts
    address private contractPricer;
    address private contractMeta;
    address private contractSVG;
    address private immutable contractToken;

    // Payout fractions
    uint48[2] private _payoutSplit;
    mapping(uint256 => uint256) private _payoutTiers;

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
        address _contractMeta,
        address _contractPriceFeed,
        address _contractToken,
        address _vrfCoordinator
        )
        C9ERC721("Collect9 ConnectX NFT", "C9X", 3333)
        C9RandomSeed(_vrfCoordinator)
    {
        // Default fee params
        _mintingFee = 5;
        _c9PortionFee = 25;
        _payoutTiers[5] = 40;
        _payoutTiers[7] = 70;
        _payoutTiers[9] = 100;
        _payoutSplit = [uint48(25), 75];

        // Default balance params
        // So the first mint doesn't have the cost to assign these
        _balance = 0;
        _c9Fees = 0;
        
        // Starting round params
        _reactivationThreshold = 3;
        _roundId = 1;
        _modulus = IC9Token(_contractToken).totalSupply();
        
        // Linked contracts
        contractPricer = _contractPriceFeed;
        contractToken = _contractToken;
    }

    /*
     * @dev Checks if address is the same before update. There are 
     * a few functions that update addresses where this is used.
     */ 
    modifier addressNotSame(address _old, address _new) {
        if (_old == _new) {
            revert AddressAlreadySet();
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
                // 3. If expired but and not a prior winning board, then revert
                if (_priorWinners[tokenId] == 0) {
                    revert ExpiredToken(tokenId, _tokenRoundId, _roundId);
                }
            }
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    
    /**
     * @dev Minting requirements called in mint() and mintPool().
     */
    function _mintReqs(address _caller, uint256 _msgValue, uint256 N)
        private {
            // 1. Make sure N > 0
            if (N == 0) {
                revert ZeroMintError();
            }
            // 2. Validate batch size (to prevent VRF from failing)
            if (N > MAX_MINT_BATCH_SIZE) {
                revert BatchSizeTooLarge(MAX_MINT_BATCH_SIZE, N);
            }
            // 3. Make sure paid amount equals the minting fee
            uint256 mintingFeeWei = getMintingFee(N);
            if (_msgValue != mintingFeeWei) {
                revert InvalidPaymentAmount(mintingFeeWei, _msgValue);
            }
            // 4. Update contract balances
            _balance += ((100-_c9PortionFee) * _msgValue/100);
            _c9Fees += (_c9PortionFee*_msgValue/100);
            // 5. Request random data from the VRF for this batch of tokens
            requestRandomWords(_caller, _tokenCounter, N);
    }

    /*
     * @dev Sets the game board a single _tokenId.
     */
    function _setTokenGameBoard(uint256 _tokenId, uint256 _currentRoundId, uint256 _randomSeed)
        private {
            _owners[_tokenId] |= _currentRoundId<<POS_ROUND_ID;
            _owners[_tokenId] |= _randomSeed<<POS_SEED;
    }

    /*
     * @dev Sets the game boards for _tokenId plus 
     * any additional tokens as part of its minting batch.
     */
    function _setTokenGameBoards(uint256 _tokenId, uint256 N, uint256 _randomSeed)
        private {
            uint256 _currentRoundId = _roundId; // Read from storage one time
            uint256 _tokenIdMax = _tokenId+N-1;
            for (_tokenId; _tokenId<_tokenIdMax;) {
                _setTokenGameBoard(_tokenId, _currentRoundId, _randomSeed);
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
            and unnecessary _randomSeed += operation.
            */
            _setTokenGameBoard(_tokenIdMax, _currentRoundId, _randomSeed);
    }

    /*
     * @dev Store data for the winners. The data is used 
     * for svg display purposes as well as enforced allowing 
     * exchange of prior won tokens.
     */
    function _storeWinner(uint256 tokenId, address winner, uint256 _gameSize, uint256[] memory _sortedIndices)
        private {
            // 1. Increment winner count
            unchecked {++_winnerCounter;} 
            // 2. Create winning data
            uint256 winnerData = uint256(uint160(winner));
            winnerData |= _winnerCounter<<WPOS_WINNING_ID;
            winnerData |= _gameSize<<WPOS_GAMESIZE;
            uint256 _offset = WPOS_INDICES;
            for (uint256 i; i<_gameSize;) {
                winnerData |= _sortedIndices[i]<<_offset;
                unchecked {
                    _offset += 8;
                    ++i;
                }
            }
            // 3. Store winning data
            _priorWinners[tokenId] = winnerData;
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
            // V2. If it exists, validate the _msgSender() is the tokenId owner
            if (ownerOf(tokenId) != _msgSender()) {
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
            More rules can be added in the future to allow for more ways to 
            win aside from tokenOwner. This will have to be done via separate 
            contract.
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
            _storeWinner(
                tokenId,
                _ownerOf(tokenId),
                _gameSize,
                _sortedIndices
            );
            
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
            W5. Process the payouts. If the owner of tokenId (_msgSender()) 
            is the same as _tokenOwner of the winning indices, then the 
            owner of tokenId (_msgSender()) will get both payouts since 
            _msgSender() will equal _tokenOwner.
            */
            (bool success,) = payable(_msgSender()).call{value: split1}("");
            if(!success) {
                revert SplitPaymentFailure(
                    address(this),
                    _msgSender(),
                    split1
                );
            }
            (success,) = payable(_tokenOwner).call{value: split0}("");
            if(!success) {
                revert SplitPaymentFailure(
                    address(this),
                    _msgSender(),
                    split0
                );
            }
            emit Winner(_msgSender(), _tokenOwner, tokenId);
    }

    /**
     * @dev Returns game pot information based on _gameSize.
     * The winner gets payout[1] and the owner of the C9Ts 
     * that forms the winning array gets payout[0].
     * The sum of the return is the full payout for when the winner 
     * also owns the C9T NFTs that formed the winning array.
     */
    function currentPotSplit(uint256 _gameSize)
        public view override
        returns(uint256 payout0, uint256 payout1) {
            uint256 _winningPayouts = _balance*_payoutTiers[_gameSize]/100;
            payout0 = _payoutSplit[0]*_winningPayouts/100;
            payout1 = _payoutSplit[1]*_winningPayouts/100;
    }

    /**
     * @dev Returns the current active roundId of the game.
     */
    function currentRoundId()
        external view
        override
        returns (uint256) {
            return _roundId;
    }

    /**
     * @dev A deposit function if/when needed for the 
     * next round. For example, the first round will 
     * require an initial deposit by the contract owner to get 
     * the game going. The owner of the contract may also 
     * mint NFTs to start up the pot.
     */
    function deposit()
        external payable
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _balance += msg.value;
    }

    /**
     * @dev Second part of the minting.
     * Once the random number request has been fulfilled, the 
     * contract will mint the NFTs to the requester who has 
     * already paid the minting fee.
     * The tokenId is number of mints is stored in the 
     * statusRequests struct.
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords)
        internal override {
            // 1. Makes sure the requestId exists and emits event
            super.fulfillRandomWords(_requestId, _randomWords);
            // 2. The requestId exists, get the tokenId and number of mints for this request
            uint256 _statusRequest = statusRequests[_requestId];
            uint256 tokenId = uint256(uint24(_statusRequest));
            uint256 N = _statusRequest>>24;
            // 3. Finish minting with VRF data
            if (N == 1) {
                _setTokenGameBoard(tokenId, _roundId, _randomWords[0]);
            }
            else {
                _setTokenGameBoards(tokenId, N, _randomWords[0]);
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

    /**
     * @dev Mint function. This function alone does not finalize the token 
     * mints. Although tokens are minted, they still need their data to be 
     * filled in with random data by the VRF. The tokens are not in play 
     * until the VRF returns the random data because the token's roundId 
     * will be set to zero until then.
     */
    function mint(uint256 N)
        external payable
        notFrozen() {
            // 1-5. Check minting requirements  are met
            _mintReqs(_msgSender(), msg.value, N);
            // 6. Mint the tokens (allocate space) with blank data
            _safeMint(_msgSender(), N);
    }

    /**
     * @dev Pool mint function. This allows users to "pool" funds 
     * together in a single mint batch. Batch minting has much lower gas 
     * fees per token as the users all share the same overhead 
     * from the VRF and game contract call.
     * 
     * The format of the input is MintAddressPool or an array of:
     * [to (address): the address to mint, N (uint96): the numer of tokens to mint to to]
     *
     * It is up to _msgSender() to pay the full fee for all minters, 
     * thus such a pool should either be arranged between trusted 
     * individuals only, or an external smart contract that will call 
     * this method when a certain threshold (such as number of mints) 
     * has been reached.
     */
    function mintPool(MintAddressPool[] calldata addressPool)
        external payable
        notFrozen() {
            // 1. Get the total number of mints of the pool
            uint256 _poolSize = addressPool.length;
            if (_poolSize < 2) {
                revert PoolNotLargeEnough(_poolSize);
            }
            uint256 N;
            for (uint256 i; i<_poolSize;) {
                N += addressPool[i].N;
                unchecked {++i;}
            }
            // 2-6. Check minting requirements  are met
            _mintReqs(_msgSender(), msg.value, N);
            // 7. Mint the tokens (allocate space) with blank data to pool
            for (uint256 i; i<_poolSize;) {
                _safeMint(addressPool[i].to, addressPool[i].N);
                unchecked {++i;}
            }
    }

    /**
     * @dev Returns the unpacked data of priorWinner tokenId. If it does not exist, 
     * then this will return all zeros.
     */
    function priorWinnerData(uint256 tokenId)
        external view override
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

    function reactivationFee(uint256[] calldata tokenIds)
        public view
        returns (uint256 reactivateFeeUSD) {
            uint256 N = tokenIds.length;
            uint256 _currentMintingFee = _mintingFee;
            uint256 _currentRoundId = _roundId;
            for (uint256 i; i<N;) {
                // 1. Add the reactivation fee for this token
                reactivateFeeUSD += (
                    (_currentRoundId - uint256(uint16(_owners[tokenIds[i]]>>POS_ROUND_ID))) * _currentMintingFee
                );
                unchecked {++i;}
            }
    }

    /**
     * @dev Allows user to reactivate an expired token. This allows 
     * users to continue board progression, albeit at a fees.
     * The fees are used to sustain the game. To prevent 
     * users from continuing to playing with deactivated boards
     * and then only reactivating upon reaching a win, the 
     * reactivation fee is proportional to the number of rounds 
     * that have completed since reactivating the board. This 
     * ensures that new minters are not a huge disadvantage.
     */
    function reactivate(uint256[] calldata tokenIds)
        external payable {
            uint256 N = tokenIds.length;
            if (N == 0) {
                revert ZeroMintError();
            }
            // Copy from storage once
            uint256 _currentRoundId = _roundId;
            address _tokenOwner;
            for (uint256 i; i<N;) {
                // 1. Check _msgSender() is token owner
                _tokenOwner = address(uint160(_owners[tokenIds[i]]));
                if (_msgSender() != _tokenOwner) {
                    revert CallerNotOwnerOrApproved();
                }
                // 2. Update the token's roundId to the current one
                _owners[tokenIds[i]] = _setTokenParam(
                    _owners[tokenIds[i]],
                    POS_ROUND_ID,
                    _currentRoundId,
                    type(uint16).max
                );
            }
            // 3. Check the paymount value is correct
            uint256 reactivationFeeWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(
                reactivationFee(tokenIds)
            );
            if (msg.value != reactivationFeeWei) {
                revert InvalidPaymentAmount(reactivationFeeWei, msg.value);
            }
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractMeta(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractMeta, _address) {
            contractMeta = _address;
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractPricer, _address) {
            contractPricer = _address;
    }

    /**
     * @dev Sets the SVG display contract address.
     * This allows SVG display to be updated.
     */
    function setContractSVG(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractSVG, _address) {
            contractSVG = _address;
    }

    /**
     * @dev Sets the C9 fee fraction.
     */
    function setFeeFraction(uint256 _fraction)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _c9PortionFee = _fraction;
    }

    /**
     * @dev Enables or disables the automatic
     * contract freezer.
     */
    function setFreezer(bool _val)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _freezerEnabled = _val;
    }

    /**
     * @dev Sets the token minting fee in USD.
     */
    function setMintingFee(uint256 fee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _mintingFee = fee;
    }

    /**
     * @dev Sets the winning payout splits between 
     * the winner, and the tokenOwner of the winning indices.
     */
    function setPayoutSplit(uint256 winnerAmt, uint256 tokenOwnerAmt)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _payoutSplit = [uint48(winnerAmt), uint48(tokenOwnerAmt)];
    }

    /**
     * @dev Sets the different payout tiers for gameboard 
     * sizes. Since a 5x5 board is much easier to win than a 9x9 
     * board, the amount is smaller.
     */
    function setPayoutTier(uint256 tier, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _payoutTiers[tier] = amount;
    }

    /**
     * @dev Returns the SVG image as a string. This is called 
     * in the tokenURI override in b64 format.
     */
    function svgImage(uint256 tokenId, uint256 gameSize)
        public view
        returns (string memory) {
            if (_exists(tokenId)) {
                return IC9GameSVG(contractSVG).svgImage(tokenId, gameSize);
            }
            else {
                return "";
            }
    }

    /**
     * @dev Returns the unpacked data of tokenId. If it does not exist, 
     * then this will return all zeros.
     */
    function tokenData(uint256 tokenId)
        external view override
        returns (address tokenOwner, uint256 tokenRoundId, uint256 randomSeed) {
            uint256 _tokenData = _owners[tokenId];
            if (_tokenData != 0) {
                tokenOwner = address(uint160(_tokenData));
                tokenRoundId = uint256(uint16(_tokenData>>POS_ROUND_ID));
                randomSeed = uint256(uint80(_tokenData>>POS_SEED));
            }
    }

        /**
     * @dev Required override that returns fully onchain constructed 
     * json output that includes the SVG image. If a baseURI is set and 
     * the token has been upgraded and the svgOnly flag is false, call 
     * the baseURI.
     *
     * Notes:
     * It seems like if the baseURI method fails after upgrade, OpenSea
     * still displays the cached on-chain version.
     */
    function tokenURI(uint256 _tokenId)
        public view override(C9ERC721, IERC721Metadata)
        returns (string memory) {
            bytes memory image = abi.encodePacked(
                ',"image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svgImage(_tokenId, 5)))
            );
            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            IC9GameMetaData(contractMeta).metaNameDesc(_tokenId),
                            image,
                            IC9GameMetaData(contractMeta).metaAttributes(_tokenId, _reactivationThreshold)
                        )
                    )
                )
            );
    }

    /*
     * @dev Returns contract balances. The balance is returned 
     * as well for quick ease of comparison to make sure the 
     * other two balances are tracking properly.
     */
    function viewBalances()
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns(uint256 balance, uint256 c9Balance, uint256 c9Fees) {
            balance = address(this).balance;
            c9Balance = _balance;
            c9Fees = _c9Fees;
    }

    /**
     * @dev View function to see the IDs generated 
     * in the tokenId game board. This is essentially the base 
     * of the playing board from which further information like 
     * the tokenOwners are derived from.
     */
    function viewGameBoard(uint256 tokenId, uint256 _gameSize)
        external view
        override
        returns (uint256[] memory) {
            // 1. Get the size of the board
            uint256 _boardSize = _gameSize*_gameSize;
            // 2. Get the tokenId's random VRF information
            uint256 _randomExpanded = uint256(
                keccak256(
                    abi.encodePacked(uint80(_owners[tokenId]>>POS_SEED))
                )
            );
            // 3. Convert VRF information to IDs
            uint256 __modulus = _modulus; // Copy from storage one time
            uint256[] memory _c9TokenIdEnums = new uint256[](_boardSize);
            for (uint256 i; i<_boardSize;) {
                unchecked {
                    _c9TokenIdEnums[i] = uint256(_randomExpanded>>(3*i)) % __modulus;
                    ++i;
                }
            }
            return _c9TokenIdEnums;
    }

    /**
     * @dev View function that converts the base playing 
     * board to Collect9 (C9T) NFT token IDs.
     */
    function viewIndicesTokenIds(uint256 tokenId, uint256[] memory _sortedIndices)
        public view override
        returns (uint256[] memory) {
            // 1. Get the game size
            uint256 _gameSize = _sortedIndices.length;
            // 2. Get the tokenId's random VRF information
            uint256 _randomExpanded = uint256(
                keccak256(
                    abi.encodePacked(uint80(_owners[tokenId]>>POS_SEED))
                )
            );
            // 3. Convert VRF information to IDs
            uint256 __modulus = _modulus; // Copy from storage one time
            uint256 _c9EnumIndex;
            uint256[] memory _c9TokenIdEnums = new uint256[](_gameSize);
            for (uint256 i; i<_gameSize;) {
                unchecked {
                    _c9EnumIndex = uint256(_randomExpanded>>(3*_sortedIndices[i])) % __modulus;
                    _c9TokenIdEnums[i] = IC9Token(contractToken).tokenByIndex(_c9EnumIndex);
                    ++i;
                }
            }
            return _c9TokenIdEnums;
    }

    /**
     * @dev Checks if the supplied indices are a valid 
     * row, column, or diagnol based on the gameSize.
     */
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
     * @dev Fail-safe mechanism that allows contract 
     * owner to remove full balance.
     */
    function withdraw(uint256 amount, bool confirm)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (!confirm) {
                revert ActionNotConfirmed();
            }
            if (amount == 0) {
                payable(owner).transfer(address(this).balance);
                _balance = 0;
                _c9Fees = 0;
            }
            else {
                payable(owner).transfer(amount);
                _balance -= amount;
            }
    }

    /*
     * @dev Removes only the fee balance that 
     * accumulates after the completion of a 
     * round.
     */
    function withdrawFees(bool confirm)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (!confirm) {
                revert ActionNotConfirmed();
            }
            payable(owner).transfer(_c9Fees);
            _balance -= _c9Fees;
            _c9Fees = 0;
    }
}