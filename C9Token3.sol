// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Struct3.sol";
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG.sol";
import "./interfaces/IC9Redeemer24.sol";
import "./interfaces/IC9Token.sol";
import "./utils/Base64.sol";
import "./utils/Helpers.sol";


import "./utils/C9ERC721EnumBasic.sol";

contract C9Token is ERC721IdEnumBasic {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant UPDATER_ROLE  = keccak256("UPDATER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Contracts this token contract interacts with.
     */
    address private contractMeta;
    address private contractRedeemer;
    address private contractSVG;
    address private contractUpgrader;
    address private contractVH;

    /**
     * @dev Flag that may enable external (IPFS) artwork 
     * versions to be displayed in the future. The _baseURI
     * is a string[2]: index 0 is active and index 1 is 
     * for inactive.
     */
    bool public svgOnly;
    string[2] public _baseURI;

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI;

    /**
     * @dev Redemption definitions and events. preRedeemablePeriod 
     * defines how long a token must exist before it can be 
     * redeemed.
     */
    uint256 private _burnableDs;
    uint256 private _preRedeemablePeriod; //seconds

    /**
     * @dev Flag to enable or disable reserved space storage.
     */
    bool private _reservedOpen;
    
    event RedemptionAdd(
        address indexed tokenOwner,
        uint256[] indexed tokenId
    );
    event RedemptionCancel(
        address indexed tokenOwner,
        uint256 indexed batchSize
    );
    event RedemptionFinish(
        address indexed tokenOwner,
        uint256 indexed batchSize
    );
    event RedemptionRemove(
        address indexed tokenOwner,
        uint256[] indexed tokenId
    );
    event RedemptionStart(
        address indexed tokenOwner,
        uint256[] indexed tokenId
    );
    
    /**
     * @dev Mappings that hold all of the token info required to 
     * construct the 100% on chain SVG.
     * Many properties within _uTokenData that define 
     * the physical collectible are immutable by design.
     */
    mapping(uint256 => address) private _rTokenData;
    mapping(uint256 => string) private _sTokenData;
    mapping(uint256 => uint256) private _uTokenData;
    
    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenData has already been minted. The boolean determines
     * whether or not to increment the editionID. This also allows 
     * for quick external lookup on whether or not a particular 
     * combo exists within this collection.
     */
    mapping(bytes32 => bool) private _tokenComboExists;

    /**
     * @dev _mintId stores the edition minting for up to 99 editions.
     * This means that 99 of some physical collectible, differentiated 
     * only by authentication certificate id can be minted. The limit 
     * is 99 due to the SVG only being able to display 2 digits.
     */
    uint16[99] private _mintId;

    /**
     * @dev The constructor. All values can be updated after deployment.
     */
    constructor()
    ERC721("Collect9 Physically Redeemable NFTs", "C9T", 500) {
        _burnableDs = 15778463; // 6 months
        _contractURI = "collect9.io/metadata/C9T";
        _preRedeemablePeriod = 31556926; // 1 year
        svgOnly = true;
    }

    /*
     * @dev Checks if caller is a smart contract (except from 
     * a constructor).
     */ 
    modifier isContract() {
        uint256 size;
        address sender = _msgSender();
        assembly {
            size := extcodesize(sender)
        }
        if (size == 0) {
            revert CallerNotContract();
        }
        _;
    }

    /*
     * @dev Checks to see if caller is the token owner. 
     * ownerOf enforces token existing.
     */ 
    modifier isOwnerOrApproved(uint256 tokenId) {
        address tokenOwner = ownerOf(tokenId);
        if (_msgSender() != tokenOwner) {
            if (!isApprovedForAll(tokenOwner, _msgSender())) {
                revert CallerNotOwnerOrApproved(tokenId, tokenOwner, _msgSender());
            }
        }
        _;
    }

    /*
     * @dev Limits royalty inputs and updates to 10%. The token can 
     * only store 10-bits worth of royalty info, or a max of 1023. 
     * For SVG format purposes we limit to 999 instead.
     */ 
    modifier limitRoyalty(uint256 royalty) {
        if (royalty > 999) {
            revert RoyaltyTooHigh();
        }
        _;
    }

    /*
     * @dev Checks to see the token is not dead. Any status redeemed 
     * or greater is a dead status, meaning the token is forever 
     * locked.
     */
    modifier notDead(uint256 tokenId) {
        if (_currentVId(_uTokenData[tokenId]) >= REDEEMED) {
            revert TokenIsDead(tokenId);
        }
        _;
    }

    /**
     * @dev Adds metadata update so the address and age displaying 
     * on the SVG automatically update on supporting marketplaces 
     * and providers.
     * Undecided if this is worth ~1200 gas yet.
     */
    // function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
    // internal
    // override(ERC721) {
    //     super._afterTokenTransfer(from, to, firstTokenId, batchSize);
    //     if (batchSize == 1) {
    //         emit MetadataUpdate(firstTokenId);
    //     }
    //     else {
    //         emit BatchMetadataUpdate(firstTokenId, firstTokenId+batchSize);
    //     }
    // }

    /**
     * @dev Required overrides from imported contracts.
     * This one checks to make sure the token is not locked 
     * either in the redemption process, or locked due to a 
     * dead status. Frozen is a long-term fail-safe migration 
     * mechanism in case Ethereum becomes too expensive to 
     * continue transacting on.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
    internal
    override(ERC721)
    notFrozen() {
        uint256 _tokenData = _owners[tokenId];
        if ((_tokenData>>MPOS_LOCKED & BOOL_MASK) == LOCKED) {
            revert TokenIsLocked(tokenId);
        }
        if (_currentVId(_tokenData) == INACTIVE) {
            _setDataValidity(_tokenData, VALID);
            _owners[tokenId] = _tokenData;
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /*
     * @dev Since validity is looked up in many places, we have a 
     * private function for it.
     */
    function _currentVId(uint256 tokenData)
    private pure
    returns (uint256) {
        return _viewPackedData(tokenData, MPOS_VALIDITY, MSZ_VALIDITY);
    }

    //>>>>>>> CUSTOM ERC2981 START

    /*
     * @dev Since royalty info is already stored in the uTokenData,
     * we don't need a new slots for per token royalties, and can 
     * use the already existing uTokenData instead.
     */
    function _setTokenRoyalty(uint256 tokenId, address receiver, uint256 royalty)
    private {
        (address _royaltyAddress, uint256 _royaltyAmt) = royaltyInfo(tokenId, 10000);
        bool _newReceiver = receiver != _royaltyAddress;
        bool _newRoyalty = royalty != _royaltyAmt;
        if (!_newReceiver && !_newRoyalty) {
            revert RoyaltiesAlreadySet();
        }
        // Check if receiver is changed
        if (_newReceiver && receiver != address(0)) {
            if (receiver == _royaltyReceiver) {
                if (_rTokenData[tokenId] != address(0)) {
                    delete _rTokenData[tokenId];
                }
            }
            else {
                _rTokenData[tokenId] = receiver;
            }
        }
        // Set new royalty
        if (_newRoyalty) {
            _uTokenData[tokenId] = _setTokenParam(
                _uTokenData[tokenId],
                UPOS_ROYALTY,
                royalty,
                MASK_ROYALTY
            );
        }
    }

    /**
     * @dev Resets royalty information for the token id back to the 
     * global defaults.
     */
    function resetTokenRoyalty(uint256 tokenId)
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId)
    notDead(tokenId)
    external {
        _setTokenRoyalty(tokenId, _royaltyReceiver, _royalty);
    }

    /**
     * @dev Custom EIP-2981. First this checks to see if the 
     * token has a royalty receiver and fraction assigned to it.
     * If not then it defaults to the contract wide values.
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
    public view
    override
    returns (address, uint256) {
        address receiver = _rTokenData[tokenId];
        if (receiver == address(0)) {
            receiver = _royaltyReceiver;
        }
        uint256 _fraction = _royalty;
        if (_exists(tokenId)) {
            _fraction = _viewPackedData(
                _uTokenData[tokenId],
                UPOS_ROYALTY,
                USZ_ROYALTY
            );
        }
        uint256 royaltyAmount = (salePrice * _fraction) / 10000;
        return (receiver, royaltyAmount);
    }

    /**
     * @dev Set royalties due if token validity status 
     * is ROYALTIES. This is admin role instead of VALIDITY_ROLE 
     * to reduce gas costs from using a proxy contract.
     * VALIDITY_ROLE will still need to set 
     * validity status ROYALTIES beforehand.
     */
    function setRoyaltiesDue(uint256 tokenId, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId) {
        if (amount == 0) {
            revert ZeroValueError();
        }
        uint256 _tokenData = _uTokenData[tokenId];
        uint256 _tokenValidity = _currentVId(_tokenData);
        if (_tokenValidity != ROYALTIES) {
            revert IncorrectTokenValidity(ROYALTIES, _tokenValidity);
        }
        if (_viewPackedData(_tokenData, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE) == amount) {
            revert RoyaltiesAlreadySet();
        }
        _uTokenData[tokenId] = _setTokenParam(
            _tokenData,
            UPOS_ROYALTIES_DUE,
            amount,
            ROYALTIES_DUE_MASK
        );
    }

    /**
     * @dev Allows the contract owner to set royalties 
     * on a per token basis, within limits.
     * Note: set _receiver address to the null address 
     * to ignore it and use the already default set royalty address.
     * Note: Updating the receiver the first time is nearly as
     * expensive as updating both together the first time.
     */
    function setTokenRoyalty(uint256 tokenId, uint256 royalty, address receiver)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId)
    notDead(tokenId)
    limitRoyalty(royalty) {
        _setTokenRoyalty(tokenId, receiver, royalty);
    }

    //>>>>>>> CUSTOM ERC2981 END

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function _getPhysicalHash(TokenData calldata input, uint256 edition)
    private pure
    returns (bytes32) {
        bytes calldata _bData = bytes(input.sData);
        uint256 _splitIndex;
        for (_splitIndex; _splitIndex<32;) {
            if (_bData[_splitIndex] == 0x3d) {
                break;
            }
            unchecked {++_splitIndex;}
        }
        return keccak256(
            abi.encodePacked(
                edition,
                input.cntrytag,
                input.cntrytush,
                input.gentag,
                input.gentush,
                input.markertush,
                input.special,
                input.sData[:_splitIndex]
            )
        );
    }

    /**
     * @dev Minting function. This checks and sets the `_edition` based on 
     * the `TokenData` input attributes, sets the `__mintId` based on 
     * the `_edition`, sets the royalty, and then stores all of the 
     * attributes required to construct the SVG in the tightly packed 
     * `TokenData` structure.
     */
    function _setTokenData(TokenData[] calldata input)
    private {
        uint256 timestamp = block.timestamp;
        uint256 batchSize = input.length;
        TokenData calldata _input;

        bytes32 _data;
        uint256 edition;
        uint256 editionMintId;
        uint256 tokenId;
        uint256 globalMintId = totalSupply()-batchSize;

        for (uint256 i; i<batchSize;) {
            _input = input[i];

            // Get physical edition id
            edition = _input.edition;
            if (edition == 0) {
                for (edition; edition<98;) {
                    unchecked {
                        ++edition;
                        _data = _getPhysicalHash(_input, edition);
                    }
                    if (!_tokenComboExists[_data]) {
                        // Store token attribute combo
                        _tokenComboExists[_data] = true;
                        break;
                    }
                }
            }

            // Get the edition mint id
            unchecked {editionMintId = _mintId[edition]+1;}
            if (_input.mintid != 0) {
                editionMintId = _input.mintid;
            }
            else {
                _mintId[edition] = uint16(editionMintId);
            }

            // Checks
            tokenId = _input.tokenid;
            if (tokenId == 0) {
                revert ZeroTokenId();
            }
            if (edition == 0) {
                revert ZeroEdition();
            }
            if (edition > 98) {
                revert EditionOverflow(edition);
            }
            if (editionMintId == 0) {
                revert ZeroMintId();
            }

            // _owners eXtended storage
            uint256 packedToken = _owners[tokenId];
            packedToken |= timestamp<<MPOS_VALIDITYSTAMP;
            packedToken |= _input.validity<<MPOS_VALIDITY;
            packedToken |= _input.upgraded<<MPOS_UPGRADED;
            packedToken |= _input.display<<MPOS_DISPLAY;
            packedToken |= _input.locked<<MPOS_LOCKED;
            packedToken |= _input.insurance<<MPOS_INSURANCE;
            _owners[tokenId] = packedToken;

            // Additional storage in _uTokenData
            unchecked {++globalMintId;}
            packedToken = globalMintId;
            packedToken |= timestamp<<UPOS_MINTSTAMP;
            packedToken |= edition<<UPOS_EDITION;
            packedToken |= editionMintId<<UPOS_EDITION_MINT_ID;
            packedToken |= _input.cntrytag<<UPOS_CNTRYTAG;
            packedToken |= _input.cntrytush<<UPOS_CNTRYTUSH;
            packedToken |= _input.gentag<<UPOS_GENTAG;
            packedToken |= _input.gentush<<UPOS_GENTUSH;
            packedToken |= _input.markertush<<UPOS_MARKERTUSH;
            packedToken |= _input.special<<UPOS_SPECIAL;
            packedToken |= _input.raritytier<<UPOS_RARITYTIER;
            packedToken |= _input.royalty<<UPOS_ROYALTY;
            packedToken |= _input.royaltiesdue<<UPOS_ROYALTIES_DUE;
            _uTokenData[tokenId] = packedToken;

            // Store token string data for SVG
            _sTokenData[tokenId] = _input.sData;

            unchecked {++i;}
        }
    }

    function mint(uint256[] calldata tokenIds, TokenData[] calldata input)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(_msgSender(), tokenIds);
        _setTokenData(input);

        // Update minter balance
        uint256 minterBalance = balanceOf(_msgSender());
        unchecked {
            minterBalance += tokenIds.length;
        }
        _balances[_msgSender()] = _setTokenParam(
            _balances[_msgSender()],
            0,
            minterBalance,
            type(uint64).max
        );
    }

    /**
     * @dev Updates the token's data validity status.
     */
    function _setDataValidity(uint256 tokenData, uint256 vId)
    private view
    returns (uint256) {
         tokenData = _setTokenParam(
            tokenData,
            MPOS_VALIDITY,
            vId,
            MASK_VALIDITY
        );
        tokenData = _setTokenParam(
            tokenData,
            MPOS_VALIDITYSTAMP,
            block.timestamp,
            type(uint40).max
        );
        return tokenData;
    }

    /**
     * @dev Updates the token validity status.
     */
    function _setTokenValidity(uint256 tokenId, uint256 vId)
    private {
        uint256 _tokenData = _owners[tokenId];
        _tokenData = _setDataValidity(_tokenData, vId);
        // Lock if changing to a dead status (forever lock)
        if (vId >= REDEEMED) {
            _tokenData = _setTokenParam(
                _tokenData,
                MPOS_LOCKED,
                LOCKED,
                BOOL_MASK
            );
        }
        _owners[tokenId] = _tokenData;
        emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Unlocks the token. The Redeem cancel functions 
     * call this to unlock the token.
     * Modifiers are placed here as it makes it simpler
     * to enforce their conditions.
     */
    function _unlockToken(uint256 _tokenId)
        private {
            uint256 _tokenData = _owners[_tokenId];
            if ((_tokenData>>MPOS_LOCKED & BOOL_MASK) == UNLOCKED) {
                revert TokenNotLocked(_tokenId);
            }
            _tokenData = _setTokenParam(
                _tokenData,
                MPOS_LOCKED,
                UNLOCKED,
                BOOL_MASK
            );
            _owners[_tokenId] = _tokenData;
    }

    /**
     * @dev Fail-safe function that can unlock an active token.
     * This is for any edge cases that may have been missed 
     * during redeemer testing. Dead tokens are still not 
     * possible to unlock, though they may be transferred to the 
     * contract owner where they may only be burned.
     */
    function adminUnlock(uint256 _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        requireMinted(_tokenId)
        notDead(_tokenId) {
            _unlockToken(_tokenId);
    }

    /**
     * @dev To ensure the token still exists, instead of 
     * delete burning, we are sending to the zero address.
     * The token is no longer recoverable at this point.
     */
    function _burn(uint256 tokenId)
    internal
    override {
        emit Transfer(_ownerOf(tokenId), address(0), tokenId);
        delete _tokenApprovals[tokenId];
        _owners[tokenId] = _setTokenParam(
            _owners[tokenId],
            0,
            uint256(0),
            type(uint160).max
        );
    }

    /**
     * @dev Token burning. This option is not available for live 
     * tokens, or with those that have a status below REDEEMED.
     * The contract owner can still burn.
     */
    function burn(uint256 tokenId)
        public
        isOwnerOrApproved(tokenId) {
            // Contract owner can skip remaining checks
            if (_msgSender() != owner) {
                uint256 _tokenData = _owners[tokenId];
                // 1. Check token validity is a dead status
                uint256 validity = _currentVId(_tokenData);
                if (validity < REDEEMED) {
                    revert C9TokenNotBurnable(tokenId, validity);
                }
                // 2. Check the token has been dead for at least _burnableDs
                uint256 _validityStamp = uint256(uint40(_tokenData>>MPOS_VALIDITYSTAMP));
                uint256 _ds = block.timestamp - _validityStamp;
                if (_ds < _burnableDs) {
                    revert C9TokenNotBurnable(tokenId, validity);
                }
                // Zero address burn
                _burn(tokenId);
            }
            else {
                // Complete burn
                super._burn(tokenId);
                delete _uTokenData[tokenId];
                delete _sTokenData[tokenId];
                if (_rTokenData[tokenId] != address(0)) {
                    delete _rTokenData[tokenId];
                }
            }
    }

    /**
     * @dev When a single burn is too expensive but you
     * don't want to burn all.
     */
    function burn(uint256[] calldata tokenIds)
        external {
            uint256 _batchSize = tokenIds.length;
            if (_batchSize == 0) {
                revert NoOwnerSupply(_msgSender());
            }
            for (uint256 i; i<_batchSize;) {
                burn(tokenIds[i]);
                unchecked {++i;}
            }
    }

    /**
     * @dev External lookup to see if token combo exists.
     * Only returns true/false and not the details of 
     * any tokenId.
     */
    function comboExists(TokenData calldata input)
        external view
        returns (bool) {
            bytes32 _data = _getPhysicalHash(input, 0);
            return _tokenComboExists[_data];
    }

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    function contractURI()
        external view
        returns (string memory) {
            return string(abi.encodePacked(
                "https://", _contractURI, ".json"
            ));
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
        external view
        returns(
            address meta, 
            address redeemer, 
            address svg, 
            address upgrader,
            address vH
        ) {
            meta = contractMeta;
            redeemer = contractRedeemer;
            svg = contractSVG;
            upgrader = contractUpgrader;
            vH = contractVH;
    }

    /**
     * @dev uTokenData is packed into a single uint256. This function
     * returns an unpacked array. It overrides the C9Struct defintion 
     * so only the _tokenId needs to be passed in.
     */
    function getTokenParams(uint256 tokenId)
        external view
        returns(uint256[20] memory xParams) {
            uint256 data = _owners[tokenId];

            xParams[0] = uint256(uint24(data>>MPOS_XFER_COUNTER));
            xParams[1] = uint256(uint40(data>>MPOS_VALIDITYSTAMP));
            xParams[2] = _currentVId(data);
            xParams[3] = data>>MPOS_UPGRADED & BOOL_MASK;
            xParams[4] = data>>MPOS_DISPLAY & BOOL_MASK;
            xParams[5] = data>>MPOS_LOCKED & BOOL_MASK;
            xParams[6] = uint256(uint24(data>>MPOS_INSURANCE));

            data = _uTokenData[tokenId];

            xParams[7] = uint256(uint24(data));
            xParams[8] = uint256(uint40(data>>UPOS_MINTSTAMP));
            xParams[9] = _viewPackedData(data, UPOS_EDITION, USZ_EDITION);
            xParams[10] = uint256(uint16(data>>UPOS_EDITION_MINT_ID));
            xParams[11] = _viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG);
            xParams[12] = _viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH);
            xParams[13] = _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG);
            xParams[14] = _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH);
            xParams[15] = _viewPackedData(data, UPOS_MARKERTUSH, USZ_MARKERTUSH);
            xParams[16] = _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL);
            xParams[17] = _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER);
            xParams[18] = _viewPackedData(data, UPOS_ROYALTY, USZ_ROYALTY);
            xParams[19] = _viewPackedData(data, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE);
    }

    //>>>>>>> REDEEMER FUNCTIONS START

    /*
     * @dev A lot of code has been repeated (inlined) here to minimize 
     * storage reads to reduce gas cost.
     */
    function _redeemLockTokens(uint256[] calldata _tokenIds)
        private {
            uint256 _batchSize = _tokenIds.length;
            address _tokenOwner;
            uint256 _tokenId;
            uint256 _tokenData;
            for (uint256 i; i<_batchSize;) {
                _tokenId = _tokenIds[i];
                _tokenOwner = _ownerOf(_tokenId);
                if (_msgSender() != _tokenOwner) {
                    revert Unauthorized();
                }

                if (preRedeemable(_tokenId)) {
                    revert TokenPreRedeemable(_tokenId);
                }
                
                _tokenData = _owners[_tokenId];
                uint256 _validity = _currentVId(_tokenData);
                if (_validity != VALID) {
                    if (_validity == INACTIVE) {
                        /* Inactive tokens can still be redeemed and 
                        will be changed to valid as user activity 
                        will automatically fix this status. */
                        _tokenData = _setDataValidity(_tokenData, VALID);
                    }
                    else {
                        revert IncorrectTokenValidity(VALID, _validity);
                    }
                }

                // If valid and locked, can only be in redeemer.
                if ((_tokenData >> MPOS_LOCKED & BOOL_MASK) == LOCKED) {
                    revert TokenIsLocked(_tokenId);
                }
                
                // Lock the token.
                _tokenData = _setTokenParam(
                   _tokenData,
                    MPOS_LOCKED,
                    LOCKED,
                    BOOL_MASK
                );

                // Save token data back to storage.
                _owners[_tokenId] = _tokenData;

                unchecked {++i;}
            }
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function preRedeemable(uint256 _tokenId)
    public view
    requireMinted(_tokenId)
    returns (bool) {
        uint256 tokenData = _uTokenData[_tokenId];
        uint256 _ds = block.timestamp - uint256(uint40(tokenData>>UPOS_MINTSTAMP));
        return _ds < _preRedeemablePeriod;
    }

    /**
     * @dev Add tokens to an existing redemption process.
     * Once added, the token is locked from further exchange until 
     * either canceled or removed.
     */
    function redeemAdd(uint256[] calldata _tokenIds)
        external {
            _redeemLockTokens(_tokenIds);
            IC9Redeemer(contractRedeemer).add(_msgSender(), _tokenIds);
            emit RedemptionAdd(_msgSender(), _tokenIds);
    }

    /**
     * @dev Allows user to cancel redemption process and 
     * unlock tokens.
     */
    function redeemCancel()
        external {
            uint256 _redeemerData = IC9Redeemer(contractRedeemer).cancel(_msgSender());
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                if (_msgSender() != ownerOf(_tokenId)) {
                    revert Unauthorized();
                }
                _unlockToken(_tokenId);
                unchecked {
                    _tokenOffset += UINT_SIZE;
                    ++i;
                }
            }
            emit RedemptionCancel(_msgSender(), _batchSize);
    }

    /**
     * @dev Finishes redemption. Called by the redeemer contract.
     */
    function redeemFinish(uint256 _redeemerData)
        external
        onlyRole(REDEEMER_ROLE)
        isContract() {
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                _setTokenValidity(_tokenId, REDEEMED);
                unchecked {
                    _tokenOffset += UINT_SIZE;
                    ++i;
                }
            }

            address tokenOwner = ownerOf(uint256(uint24(_redeemerData>>RPOS_TOKEN1)));

            // Copy from storage first
            uint256 ownerData = _balances[tokenOwner];

            // Parameters to update
            uint256 ownerRedemptions = uint256(uint128(ownerData>>64));

            // Update redemptions count for this owner
            unchecked {
                ownerRedemptions += _batchSize;
            }

            // Set packed values in memory
            ownerData = _setTokenParam(
                ownerData,
                0,
                ownerRedemptions,
                type(uint64).max
            );

            // Copy back to memory
            _balances[tokenOwner] = ownerData;

            emit RedemptionFinish(
                _ownerOf(uint256(uint24(_redeemerData>>RPOS_TOKEN1))),
                _batchSize
            );
    }

    /**
     * @dev Allows user to remove tokens from 
     * an existing redemption process.
     */
    function redeemRemove(uint256[] calldata _tokenIds)
        external {
            IC9Redeemer(contractRedeemer).remove(_msgSender(), _tokenIds);
            uint256 _batchSize = _tokenIds.length;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = _tokenIds[i];
                if (_msgSender() != ownerOf(_tokenId)) {
                    revert Unauthorized();
                }
                _unlockToken(_tokenId);
                unchecked {++i;}
            }
            emit RedemptionRemove(_msgSender(), _tokenIds);
    }

    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     */
    function redeemStart(uint256[] calldata _tokenIds)
        external {
            _redeemLockTokens(_tokenIds);
            IC9Redeemer(contractRedeemer).start(_msgSender(), _tokenIds);
            emit RedemptionStart(_msgSender(), _tokenIds);
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
     */
    function setBurnablePeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_period > 63113852) { // 2 years max
                revert PeriodTooLong(63113852, _period);
            }
            if (_burnableDs == _period) {
                revert ValueAlreadySet();
            }
            _burnableDs = _period;
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
     */
    function setPreRedeemPeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_period > 63113852) { // 2 years max
                revert PeriodTooLong(63113852, _period);
            }
            if (_preRedeemablePeriod == _period) {
                revert ValueAlreadySet();
            }
            _preRedeemablePeriod = _period;
    }

    //>>>>>>> REDEEMER FUNCTIONS END

    //>>>>>>> SETTER FUNCTIONS START

    /**
     * @dev Updates the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork (i.e, on ipfs), the 
     * contract will need to set the IPFS location.
     */
    function setBaseUri(string calldata _newBaseURI, uint256 _idx)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(_baseURI[_idx], _newBaseURI)) {
                revert URIAlreadySet();
                
            }
            bytes calldata _bBaseURI = bytes(_newBaseURI);
            uint256 len = _bBaseURI.length;
            if (bytes1(_bBaseURI[len-1]) != 0x2f) {
                revert URIMissingEndSlash();
            }
            _baseURI[_idx] = _newBaseURI;
    }

    /**
     * @dev Sets the meta data contract address.
     */
    function setContractMeta(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractMeta, _address) {
            contractMeta = _address;
    }

    /**
     * @dev Sets the redemption contract address.
     */
    function setContractRedeemer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractRedeemer, _address) {
            contractRedeemer = _address;
            _grantRole(REDEEMER_ROLE, contractRedeemer);
    }

    /**
     * @dev Sets the SVG display contract address.
     */
    function setContractSVG(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractSVG, _address) {
            contractSVG = _address;
    }

    /**
     * @dev Sets the upgrader contract address.
     */
    function setContractUpgrader(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractUpgrader, _address) {
            contractUpgrader = _address;
            _grantRole(UPGRADER_ROLE, contractUpgrader);
    }

    /**
     * @dev Sets the contractURI.
     */
    function setContractURI(string calldata _newContractURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(_contractURI, _newContractURI)) {
                revert URIAlreadySet();
            }
            _contractURI = _newContractURI;
    }

    /**
     * @dev Sets the validity handler contract address.
     */
    function setContractVH(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractVH, _address) {
            contractVH = _address;
            _grantRole(VALIDITY_ROLE, contractVH);
    }

    /**
     * @dev Set SVG flag to either display on-chain SVG (true) or  
     * external version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     */
    function setSvgOnly(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (svgOnly == _flag) {
                revert BoolAlreadySet();
            }
            svgOnly = _flag;
    }

    /**
     * @dev Allows holder toggle display flag.
     * Flag must be set to true for upgraded / external 
     * view to show. Metadata needs to be refershed 
     * on exchanges for changes to show.
     */
    function setTokenDisplay(uint256 tokenId, bool flag)
        external
        isOwnerOrApproved(tokenId) {
            uint256 tokenData = _owners[tokenId];
            uint256 _val = tokenData>>MPOS_UPGRADED & BOOL_MASK;
            if (_val != UPGRADED) {
                revert TokenNotUpgraded(tokenId);
            }
            _val = tokenData>>MPOS_DISPLAY & BOOL_MASK;
            if (Helpers.uintToBool(_val) == flag) {
                revert BoolAlreadySet();
            }
            uint256 display = flag ? EXTERNAL_IMG : ONCHAIN_SVG;
            _owners[tokenId] = _setTokenParam(
                tokenData,
                MPOS_DISPLAY,
                display,
                BOOL_MASK
            );
            emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Allows the compressed data that is used to display the 
     * micro QR code on the SVG to be updated.
     */
    function _setTokenSData(uint256 tokenId, string calldata sData)
        private
        requireMinted(tokenId)
        notDead(tokenId) {
            _sTokenData[tokenId] = sData;
    }

    function setTokenSData(TokenSData[] calldata sData)
        external 
        onlyRole(UPDATER_ROLE) {
            uint256 _batchSize = sData.length;
            for (uint256 i; i<_batchSize;) {
                _setTokenSData(sData[i].tokenId, sData[i].sData);
                unchecked {++i;}
            }
    }

    /*
     * @dev Sets the token validity.
     */
    function setTokenValidity(uint256 tokenId, uint256 vId)
        external
        onlyRole(VALIDITY_ROLE)
        isContract()
        requireMinted(tokenId) {
            if (vId >= REDEEMED) {
                revert TokenIsDead(tokenId);
            }
            if (vId == _currentVId(_uTokenData[tokenId])) {
                revert ValueAlreadySet();
            }
            _setTokenValidity(tokenId, vId);
    }

    /**
     * @dev Sets the token as upgraded.
     */
    function setTokenUpgraded(uint256 tokenId)
        external
        onlyRole(UPGRADER_ROLE)
        isContract()
        requireMinted(tokenId)
        notDead(tokenId) {
            uint256 _tokenData = _owners[tokenId];
            if ((_tokenData>>MPOS_UPGRADED & BOOL_MASK) == UPGRADED) {
                revert TokenAlreadyUpgraded(tokenId);
            }
            _owners[tokenId] = _setTokenParam(
                _tokenData,
                MPOS_UPGRADED,
                UPGRADED,
                BOOL_MASK
            );
            emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in hmtl/xml code.
     */
    function svgImage(uint256 tokenId)
        public view
        requireMinted(tokenId)
        returns (string memory) {
            return IC9SVG(contractSVG).returnSVG(
                ownerOf(tokenId),
                tokenId,
                _uTokenData[tokenId],
                _sTokenData[tokenId]
            );
    }

    /**
     * @dev Flag that sets global toggle to freeze redemption. 
     * Users may still cancel redemption and unlock their 
     * token if in the process.
     */
    function toggleReserved(bool toggle)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_reservedOpen == toggle) {
                revert BoolAlreadySet();
            }
            _reservedOpen = toggle;
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
        public view override(ERC721)
        requireMinted(_tokenId)
        returns (string memory) {
            uint256 _tokenData = _owners[_tokenId];
            bool _externalView = (_tokenData>>MPOS_DISPLAY & BOOL_MASK) == EXTERNAL_IMG;
            bytes memory image;
            if (svgOnly || !_externalView) {
                // Onchain SVG
                image = abi.encodePacked(
                    ',"image":"data:image/svg+xml;base64,',
                    Base64.encode(bytes(svgImage(_tokenId)))
                );
            }
            else {
                // Token upgraded, get view URI based on if redeemed or not
                uint256 _viewIdx = _currentVId(_tokenData) >= REDEEMED ? URI1 : URI0;
                image = abi.encodePacked(
                    ',"image":"',
                    _baseURI[_viewIdx],
                    Helpers.tokenIdToBytes(_tokenId),
                    '.png'
                );
            }
            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            IC9MetaData(contractMeta).metaNameDesc(_tokenId, _tokenData, _sTokenData[_tokenId]),
                            image,
                            IC9MetaData(contractMeta).metaAttributes(_tokenData)
                        )
                    )
                )
            );
    }

    /**
     * @dev Disables self-destruct functionality.
     * Note: even if admin gets through the confirm 
     * is hardcoded to false.
     */
    function __destroy(address _receiver, bool confirm)
        public override
        onlyRole(DEFAULT_ADMIN_ROLE) {
            confirm = false;
            super.__destroy(_receiver, confirm);
    }

    /**
     * @dev Sets the data for the reserved (unused at mint) 
     * space. Since this storage is already paid for, it may
     * be used for expansion features that may be available 
     * later. Such features will only be available to 
     * external contracts, as this contract will have no
     * built-in parsing.
     * 112 bits remain in the reserved storage space.
     */
    function _setReserved(uint256 _tokenId, uint256 _data)
        private
        isOwnerOrApproved(_tokenId) {
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                UPOS_RESERVED,
                _data,
                type(uint112).max
            );
    }

    /**
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function setReserved(uint256[2][] calldata _data)
        external {
            if (!_reservedOpen) {
                revert ReservedSpaceNotOpen();
            }
            uint256 _batchSize = _data.length;
            for (uint256 i; i<_batchSize;) {
                _setReserved(_data[i][0], _data[i][1]);
                unchecked {++i;}
            }
    }

    /**
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function getReserved(uint256 tokenId)
    requireMinted(tokenId)
    external view
    returns (uint256) {
        uint256 tokenData = _uTokenData[tokenId];
        return tokenData>>UPOS_RESERVED;
    }
}