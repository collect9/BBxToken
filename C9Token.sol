// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./abstract/C9Struct.sol";
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG.sol";
import "./interfaces/IC9Redeemer24.sol";
import "./interfaces/IC9Token.sol";
import "./utils/Base64.sol";
import "./utils/C9ERC721.sol";
import "./utils/Helpers.sol";

contract C9Token is C9OwnerControl, C9Struct, ERC721, IC9Token {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant RESERVED_ROLE = keccak256("RESERVED_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Default royalty. These should be packed into one slot.
     * These are part of the custom EIP-2981.
     */
    address private royaltyDefaultReceiver;
    uint96 private royaltyDefaultValue;

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
    bool public svgOnly = true;
    string[2] public _baseURI;

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI = "collect9.io/metadata/C9T";

    /**
     * @dev Redemption definitions and events. preRedeemablePeriod 
     * defines how long a token must exist before it can be 
     * redeemed.
     */
    uint256 private preRedeemablePeriod = 31556926; //seconds
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
    event TokenUpgraded(
        address indexed tokenOwner,
        uint256 indexed tokenId
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
     * whether or not to increment the editionID.
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
     * @dev The constructor sets the default royalty of the tokens.
     * Default receiver is set to owner. Both can be 
     * updated after deployment.
     */
    constructor()
        ERC721("Collect9 NFTs", "C9T") {
            royaltyDefaultValue = uint96(500);
            royaltyDefaultReceiver = owner;
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

    /*
     * @dev Checks if caller is a smart contract (except from 
     * a constructor).
     */ 
    modifier isContract() {
        uint256 size;
        address sender = msg.sender;
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
     */ 
    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = _ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            revert Unauthorized();
        }
        _;
    }

    /*
     * @dev Limits royalty inputs and updates to 10%.
     */ 
    modifier limitRoyalty(uint256 _royalty) {
        if (_royalty > 999) {
            revert RoyaltyTooHigh();
        }
        _;
    }

    /*
     * @dev Checks to see the token is not dead. Any status redeemed 
     * or greater is a dead status, meaning the token is forever 
     * locked.
     */
    modifier notDead(uint256 _tokenId) {
        if (uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY)) >= REDEEMED) {
            revert TokenIsDead(_tokenId);
        }
        _;
    }

    /*
     * @dev Checks to see if the tokenId exists.
     */
    modifier tokenExists(uint256 _tokenId) {
        if (!_exists(_tokenId)) {
            revert InvalidToken(_tokenId);
        }
        _;
    }

    /**
     * @dev Required overrides from imported contracts.
     * This one checks to make sure the token is not locked 
     * either in the redemption process, or locked due to a 
     * dead status. Frozen is a long-term fail-safe migration 
     * mechanism in case Ethereum becomes too expensive to 
     * continue transacting on.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
        )
        internal
        override(ERC721)
        notFrozen() {
            uint256 _tokenData = _uTokenData[tokenId];
            if (_tokenData>>POS_LOCKED & BOOL_MASK == LOCKED) {
                revert TokenIsLocked(tokenId);
            }
            // Adds ~3K extra gas to tx if true
            if (uint256(uint8(_tokenData>>POS_VALIDITY)) == INACTIVE) {
                _setTokenValidity(tokenId, VALID);
            }
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev IERC2981 for marketplaces to see EIP-2981.
     */
    function supportsInterface(bytes4 interfaceId)
        public view
        override(IERC165, ERC721, AccessControl)
        returns (bool) {
            return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    //>>>>>>> CUSTOM ERC2981 START

    /*
     * @dev Since royalty info is already stored in the uTokenData,
     * we don't need a new slots for per token royalties, and can 
     * use the already existing uTokenData instead.
     */
    function _setTokenRoyalty(uint256 _tokenId, address _receiver, uint256 _royalty)
        private {
            (address _royaltyAddress, uint256 _royaltyAmt) = royaltyInfo(_tokenId, 10000);
            bool _newReceiver = _receiver != _royaltyAddress;
            bool _newRoyalty = _royalty != _royaltyAmt;
            if (!_newReceiver && !_newRoyalty) {
                revert RoyaltiesAlreadySet();
            }

            if (_newReceiver && _receiver != address(0)) {
                if (_receiver == royaltyDefaultReceiver) {
                    if (_rTokenData[_tokenId] != address(0)) {
                        delete _rTokenData[_tokenId];
                    }
                }
                else {
                    _rTokenData[_tokenId] = _receiver;
                }
            }
            
            if (_newRoyalty) {
                _uTokenData[_tokenId] = _setTokenParam(
                    _uTokenData[_tokenId],
                    POS_ROYALTY,
                    _royalty,
                    type(uint16).max
                );
            }
    }

    /**
     * @dev Resets royalty information for the token id back to the 
     * global defaults.
     */
    function resetTokenRoyalty(uint256 _tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notDead(_tokenId)
        external {
            _setTokenRoyalty(_tokenId, royaltyDefaultReceiver, royaltyDefaultValue);
    }

    /**
     * @dev Custom EIP-2981.
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        public view override
        returns (address, uint256) {
            address receiver = _rTokenData[_tokenId];
            if (receiver == address(0)) {
                receiver = royaltyDefaultReceiver;
            }
            uint256 _fraction = royaltyDefaultValue;
            if (_exists(_tokenId)) {
                _fraction = uint256(uint16(_uTokenData[_tokenId]>>POS_ROYALTY));
            }
            uint256 royaltyAmount = (_salePrice * _fraction) / 10000;
            return (receiver, royaltyAmount);
    }

    /**
     * @dev Set royalties due if token validity status 
     * is ROYALTIES. This is admin role instead of VALIDITY_ROLE 
     * to reduce gas costs. VALIDITY_ROLE will need to set 
     * validity status ROYALTIES beforehand.
     */
    function setRoyaltiesDue(uint256 _tokenId, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId) {
            if (_amount == 0) {
                revert ZeroValue();
            }
            uint256 _tokenData = _uTokenData[_tokenId];
            uint256 _tokenValidity = uint256(uint8(_tokenData>>POS_VALIDITY));
            if (_tokenValidity != ROYALTIES) {
                revert IncorrectTokenValidity(ROYALTIES, _tokenValidity);
            }
            if (uint256(uint16(_tokenData>>POS_ROYALTIESDUE)) == _amount) {
                revert RoyaltiesAlreadySet();
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_ROYALTIESDUE,
                _amount,
                type(uint16).max
            );
    }

    /**
     * @dev Allows contract to have a separate royalties receiver 
     * address from owner. The default receiver is owner.
     */
    function setRoyaltyDefaultReceiver(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(royaltyDefaultReceiver, _address) {
            if (_address == address(0)) {
                revert ZeroAddressInvalid();
            }
            royaltyDefaultReceiver = _address;
    }

    /**
     * @dev Sets the default royalties amount.
     */
    function setRoyaltyDefaultValue(uint256 _royaltyDefaultValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_royaltyDefaultValue) {
            if (_royaltyDefaultValue == royaltyDefaultValue) {
                revert ValueAlreadySet();
            }
            royaltyDefaultValue = uint96(_royaltyDefaultValue);
    }

    /**
     * @dev Allows the contract owner to set royalties 
     * on a per token basis, within limits.
     * Note: set _receiver address to the null address 
     * to ignore it and use the already default set royalty address.
     * Note: Updating the receiver the first time is nearly as
     * expensive as updating both together the first time.
     */
    function setTokenRoyalty(
        uint256 _tokenId,
        uint256 _newRoyalty,
        address _receiver
        )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notDead(_tokenId)
        limitRoyalty(_newRoyalty) {
            _setTokenRoyalty(_tokenId, _receiver, _newRoyalty);
    }

    //>>>>>>> CUSTOM ERC2981 END

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function _getPhysicalHash(TokenData calldata _input, uint256 _edition)
        private pure
        returns (bytes32) {
            bytes memory _bData = bytes(_input.sData);
            uint256 _splitIndex;
            for (_splitIndex; _splitIndex<32;) {
                if (_bData[_splitIndex] == 0x3d) {
                    break;
                }
                unchecked {++_splitIndex;}
            }
            return keccak256(
                abi.encodePacked(
                    _edition,
                    _input.cntrytag,
                    _input.cntrytush,
                    _input.gentag,
                    _input.gentush,
                    _input.markertush,
                    _input.special,
                    _input.sData[:_splitIndex]
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
    function _mint1(TokenData calldata _input)
        private
        limitRoyalty(_input.royalty) {
            // Get physical edition id
            uint256 _edition = _input.edition;
            bytes32 _data;
            if (_edition == 0) {
                for (_edition; _edition<98;) {
                    unchecked {
                        ++_edition;
                        _data = _getPhysicalHash(_input, _edition);
                    }
                    if (!_tokenComboExists[_data]) {
                        break;
                    }
                }
            }

            // Get the edition mint id
            uint256 __mintId;
            unchecked {__mintId = _mintId[_edition]+1;}
            if (_input.mintid != 0) {
                __mintId = _input.mintid;
            }
            else {
                _mintId[_edition] = uint16(__mintId);
            }

            // Checks
            uint256 _tokenId = _input.tokenid;
            if (_tokenId == 0) {
                revert ZeroTokenId();
            }
            if (_edition == 0) {
                revert ZeroEdition();
            }
            if (_edition >= 99) {
                revert EditionOverflow(_edition);
            }
            if (__mintId == 0) {
                revert ZeroMintId();
            }

            // Store token uint data
            uint256 _packedToken;
            uint256 _timestamp = block.timestamp;
            _packedToken |= _input.upgraded<<POS_UPGRADED;
            _packedToken |= _input.display<<POS_DISPLAY;
            _packedToken |= _input.locked<<POS_LOCKED;
            _packedToken |= _input.validity<<POS_VALIDITY;
            _packedToken |= _edition<<POS_EDITION;
            _packedToken |= _input.cntrytag<<POS_CNTRYTAG;
            _packedToken |= _input.cntrytush<<POS_CNTRYTUSH;
            _packedToken |= _input.gentag<<POS_GENTAG;
            _packedToken |= _input.gentush<<POS_GENTUSH;
            _packedToken |= _input.markertush<<POS_MARKERTUSH;
            _packedToken |= _input.special<<POS_SPECIAL;
            _packedToken |= _input.raritytier<<POS_RARITYTIER;
            _packedToken |= __mintId<<POS_MINTID;
            _packedToken |= _input.royalty<<POS_ROYALTY;
            _packedToken |= _input.royaltiesdue<<POS_ROYALTIESDUE;
            _packedToken |= _tokenId<<POS_TOKENID;
            _packedToken |= _timestamp<<POS_VALIDITYSTAMP;
            _packedToken |= _timestamp<<POS_MINTSTAMP;
            _uTokenData[_tokenId] = _packedToken;

            // Store token string data
            _sTokenData[_tokenId] = _input.sData;

            // Store token attribute combo
            _tokenComboExists[_data] = true;

            // Mint token
            _mint(msg.sender, _tokenId);
    }

    /**
     * @dev Internal function that returns if the token is
     * preredeemable or not.
     */
    function _preRedeemable(uint256 _tokenData)
        private view
        returns (bool) {
            uint256 _ds = block.timestamp-uint256(uint40(_tokenData>>POS_MINTSTAMP));
            return _ds < preRedeemablePeriod;
    }

    /**
     * @dev Updates the token validity status.
     */
    function _setTokenValidity(uint256 _tokenId, uint256 _vId)
        private {
            uint256 _tokenData = _uTokenData[_tokenId];
            _tokenData = _setTokenParam(
                _tokenData,
                POS_VALIDITY,
                _vId,
                type(uint8).max
            );
            _tokenData = _setTokenParam(
                _tokenData,
                POS_VALIDITYSTAMP,
                block.timestamp,
                type(uint40).max
            );
            // Lock if changing to a dead status (forever lock)
            if (_vId >= REDEEMED) {
                _tokenData = _setTokenParam(
                    _tokenData,
                    POS_LOCKED,
                    LOCKED,
                    BOOL_MASK
                );
            }
            _uTokenData[_tokenId] = _tokenData;
    }

    /**
     * @dev Unlocks the token. The Redeem cancel functions 
     * call this to unlock the token.
     * Modifiers are placed here as it makes it simpler
     * to enforce their conditions.
     */
    function _unlockToken(uint256 _tokenId)
        private {
            uint256 _tokenData = _uTokenData[_tokenId];
            if (_tokenData>>POS_LOCKED & BOOL_MASK == UNLOCKED) {
                revert TokenNotLocked(_tokenId);
            }
            _tokenData = _setTokenParam(
                _tokenData,
                POS_LOCKED,
                UNLOCKED,
                BOOL_MASK
            );
            _uTokenData[_tokenId] = _tokenData;
    }

    /**
     * @dev Fail-safe function that can unlock an active token.
     * This is for any edge cases that may have been missed 
     * during redeemer testing. Dead tokens are still not 
     * possible to unlock.
     */
    function adminUnlock(uint256 _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notDead(_tokenId) {
            _unlockToken(_tokenId);
    }

    /**
     * @dev The token burning required for the redemption process.
     * Require statement is the same as in ERC721Burnable.
     * Note the `tokenComboExists` of the token is not removed, thus 
     * once the `edition` of any burned token cannot be replaced, but 
     * instead will keep incrementing.
     */
    function burn(uint256 _tokenId)
        public
        isOwner(_tokenId) {
            _burn(_tokenId);
            delete _uTokenData[_tokenId];
            delete _sTokenData[_tokenId];
            if (_rTokenData[_tokenId] != address(0)) {
                delete _rTokenData[_tokenId];
            }
    }

    /**
     * @dev Bulk burn function for convenience.
     */
    function burnAll(bool confirm)
        external {
            if (!confirm) {
                revert ActionNotConfirmed();
            }
            uint256 ownerSupply = balanceOf(msg.sender);
            if (ownerSupply == 0) {
                revert NoOwnerSupply(msg.sender);
            }
            for (uint256 i; i<ownerSupply;) {
                burn(tokenOfOwnerByIndex(msg.sender, 0));
                unchecked {++i;}
            }
    }

    /**
     * @dev When a single burn is too expensive but you
     * don't want to burn all.
     */
    function burnBatch(bool confirm, uint256[] calldata _tokenId)
        external {
            if (!confirm) {
                revert ActionNotConfirmed();
            }
            uint256 _batchSize = _tokenId.length;
            if (_batchSize == 0) {
                revert NoOwnerSupply(msg.sender);
            }
            for (uint256 i; i<_batchSize;) {
                burn(_tokenId[i]);
                unchecked {++i;}
            }
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
    function getTokenParams(uint256 _tokenId)
        external view override
        returns(uint256[19] memory params) {
            uint256 _packedToken = _uTokenData[_tokenId];
            params[0] = _packedToken>>POS_UPGRADED & BOOL_MASK;
            params[1] = _packedToken>>POS_DISPLAY & BOOL_MASK;
            params[2] = _packedToken>>POS_LOCKED & BOOL_MASK;
            params[3] = uint256(uint8(_packedToken>>POS_VALIDITY));
            params[4] = uint256(uint8(_packedToken>>POS_EDITION));
            params[5] = uint256(uint8(_packedToken>>POS_CNTRYTAG));
            params[6] = uint256(uint8(_packedToken>>POS_CNTRYTUSH));
            params[7] = uint256(uint8(_packedToken>>POS_GENTAG));
            params[8] = uint256(uint8(_packedToken>>POS_GENTUSH));
            params[9] = uint256(uint8(_packedToken>>POS_MARKERTUSH));
            params[10] = uint256(uint8(_packedToken>>POS_SPECIAL));
            params[11] = uint256(uint8(_packedToken>>POS_RARITYTIER));
            params[12] = uint256(uint16(_packedToken>>POS_MINTID));
            params[13] = uint256(uint16(_packedToken>>POS_ROYALTY));
            params[14] = uint256(uint16(_packedToken>>POS_ROYALTIESDUE));
            params[15] = uint256(uint32(_packedToken>>POS_TOKENID));
            params[16] = uint256(uint40(_packedToken>>POS_VALIDITYSTAMP));
            params[17] = uint256(uint40(_packedToken>>POS_MINTSTAMP));
            params[18] = uint256(_packedToken>>POS_RESERVED);
    }

    /**
     * @dev Batch mint. Makes the overall minting process faster and cheaper 
     * on average per mint.
     */
    function mintBatch(TokenData[] calldata _input)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _input.length;
            for (uint256 i; i<_batchSize;) {
                _mint1(_input[i]);
                unchecked {++i;}
            }
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
                if (msg.sender != _tokenOwner) {
                    revert Unauthorized();
                }

                _tokenData = _uTokenData[_tokenId];
                if (_preRedeemable(_tokenData)) {
                    revert TokenPreRedeemable(_tokenId);
                }
                
                uint256 _validity = uint256(uint8(_tokenData>>POS_VALIDITY));
                if (_validity != VALID) {
                    if (_validity == INACTIVE) {
                        /* Inactive tokens can still be redeemed and 
                        will be changed to valid as user activity 
                        will automatically fix this status. */
                        _tokenData = _setTokenParam(
                            _tokenData,
                            POS_VALIDITY,
                            VALID,
                            type(uint8).max
                        );
                        _tokenData = _setTokenParam(
                            _tokenData,
                            POS_VALIDITYSTAMP,
                            block.timestamp,
                            type(uint40).max
                        );
                    }
                    else {
                        revert IncorrectTokenValidity(VALID, _validity);
                    }
                }

                // If valid and locked, can only be in redeemer.
                if (_tokenData>>POS_LOCKED & BOOL_MASK == LOCKED) {
                    revert TokenIsLocked(_tokenId);
                }
                
                // Lock the token.
                _tokenData = _setTokenParam(
                   _tokenData,
                    POS_LOCKED,
                    LOCKED,
                    BOOL_MASK
                );

                // Save token data back to storage.
                _uTokenData[_tokenId] = _tokenData;
                unchecked {++i;}
            }
    }

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function preRedeemable(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns (bool) {
            return _preRedeemable(_uTokenData[_tokenId]);
    }

    /**
     * @dev Add tokens to an existing redemption process.
     * Once added, the token is locked from further exchange until 
     * either canceled or removed.
     */
    function redeemAdd(uint256[] calldata _tokenIds)
        external override {
            _redeemLockTokens(_tokenIds);
            IC9Redeemer(contractRedeemer).add(msg.sender, _tokenIds);
            emit RedemptionAdd(msg.sender, _tokenIds);
    }

    /**
     * @dev Allows user to cancel redemption process and 
     * unlock tokens.
     */
    function redeemCancel()
        external override {
            uint256 _redeemerData = IC9Redeemer(contractRedeemer).cancel(msg.sender);
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                if (msg.sender != _ownerOf(_tokenId)) {
                    revert Unauthorized();
                }
                _unlockToken(_tokenId);
                unchecked {
                    _tokenOffset += UINT_SIZE;
                    ++i;
                }
            }
            emit RedemptionCancel(msg.sender, _batchSize);
    }

    /**
     * @dev Finishes redemption. Called by the redeemer contract.
     */
    function redeemFinish(uint256 _redeemerData)
        external override
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
        external override {
            IC9Redeemer(contractRedeemer).remove(msg.sender, _tokenIds);
            uint256 _batchSize = _tokenIds.length;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = _tokenIds[i];
                if (msg.sender != _ownerOf(_tokenId)) {
                    revert Unauthorized();
                }
                _unlockToken(_tokenId);
                unchecked {++i;}
            }
            emit RedemptionRemove(msg.sender, _tokenIds);
    }

    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     */
    function redeemStart(uint256[] calldata _tokenIds)
        external override {
            _redeemLockTokens(_tokenIds);
            IC9Redeemer(contractRedeemer).start(msg.sender, _tokenIds);
            emit RedemptionStart(msg.sender, _tokenIds);
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
     */
    function setPreRedeemPeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (preRedeemablePeriod == _period) {
                revert ValueAlreadySet();
            }
            if (_period > 63113852) { // 2 years max
                revert PeriodTooLong(63113852, _period);
            }
            preRedeemablePeriod = _period;
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
    function setTokenDisplay(uint256 _tokenId, bool _flag)
        external
        isOwner(_tokenId) {
            uint256 _tokenData = _uTokenData[_tokenId];
            uint256 _val = _tokenData>>POS_UPGRADED & BOOL_MASK;
            if (_val != UPGRADED) {
                revert TokenNotUpgraded(_tokenId);
            }
            _val = _tokenData>>POS_DISPLAY & BOOL_MASK;
            if (Helpers.uintToBool(_val) == _flag) {
                revert BoolAlreadySet();
            }
            uint256 _display = _flag ? EXTERNAL_IMG : ONCHAIN_SVG;
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_DISPLAY,
                _display,
                BOOL_MASK
            );
    }

    /**
     * @dev Allows the compressed data that is used to display the 
     * micro QR code on the SVG to be updated.
     */
    function setTokenSData(uint256 _tokenId, string memory _sData)
        public 
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notDead(_tokenId) {
            _sTokenData[_tokenId] = _sData;
    }

    /*
     * @dev Sets the token validity.
     */
    function setTokenValidity(uint256 _tokenId, uint256 _vId)
        external override
        onlyRole(VALIDITY_ROLE)
        isContract()
        tokenExists(_tokenId)
        notDead(_tokenId) {
            if (_vId == REDEEMED) {
                // 6, 7, 8 are dead ids for invalid active ids 1, 2, 3
                revert InvalidVId(_vId);
            }
            uint256 _currentVId = uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY));
            if (_vId == _currentVId) {
                revert ValueAlreadySet();
            }
            _setTokenValidity(_tokenId, _vId);
    }

    /**
     * @dev Sets the token as upgraded.
     */
    function setTokenUpgraded(uint256 _tokenId)
        external override
        onlyRole(UPGRADER_ROLE)
        isContract()
        tokenExists(_tokenId)
        notDead(_tokenId) {
            uint256 _tokenData = _uTokenData[_tokenId];
            if (_tokenData>>POS_UPGRADED & BOOL_MASK == UPGRADED) {
                revert TokenAlreadyUpgraded(_tokenId);
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_UPGRADED,
                UPGRADED,
                BOOL_MASK
            );
            emit TokenUpgraded(_ownerOf(_tokenId), _tokenId);
    }

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in hmtl/xml code.
     */
    function svgImage(uint256 _tokenId)
        public view
        tokenExists(_tokenId)
        returns (string memory) {
            return IC9SVG(contractSVG).returnSVG(
                _ownerOf(_tokenId),
                _uTokenData[_tokenId],
                _sTokenData[_tokenId]
            );
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
        public view override(ERC721, IERC721Metadata)
        tokenExists(_tokenId)
        returns (string memory) {
            uint256 _tokenData = _uTokenData[_tokenId];
            bool _externalView = _tokenData>>POS_DISPLAY & BOOL_MASK == EXTERNAL_IMG;
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
                uint256 _viewIdx = uint256(uint8(_tokenData>>POS_VALIDITY)) >= REDEEMED ? URI1 : URI0;
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
                            IC9MetaData(contractMeta).metaNameDesc(_tokenData, _sTokenData[_tokenId]),
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
     * 21 bits remain in the token storage slot.
     */
    function __setReserved(uint256 _tokenId, uint256 _data)
        external
        onlyRole(RESERVED_ROLE) {
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_RESERVED,
                _data,
                2097151
            );
    }
}