// SPDX-License-Identifier: MIT
pragma solidity >0.8.10;
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./utils/ERC721opt.sol";

import "./C9MetaData.sol";
import "./C9OwnerControl.sol";
import "./C9Redeemer24.sol";
import "./C9Struct.sol";
import "./C9SVG.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";

error AddressAlreadySet(); //0xf62c2d82
error BatchSizeTooLarge(uint256 maxSize, uint256 received); //0x01df19f6
error CallerNotContract(); //0xa85366a7
error EditionOverflow(uint256 received); //0x5723b5d1
error IncorrectTokenValidity(uint256 expected, uint256 received); //0xe8c07318
error InvalidVId(uint256 received); //0xcf8cffb0
error NoOwnerSupply(address sender); //0x973d81af
error PeriodTooLong(uint256 maxPeriod, uint256 received); //0xd36b55de
error RoyaltiesAlreadySet(); //0xe258016d
error RoyaltyTooHigh(); //0xc2b03beb
error ValueAlreadySet(); //0x30a4fcdc
error URIAlreadySet(); //0x82ccdaca
error URIMissingEndSlash(); //0x21edfe88
error TokenAlreadyUpgraded(uint256 tokenId); //0xb4aab4a3
error TokenIsDead(uint256 tokenId); //0xf87e5785
error TokenIsLocked(uint256 tokenId); //0xdc8fb341
error TokenNotLocked(uint256 tokenId); //0x5ef77436
error TokenNotUpgraded(uint256 tokenId); //0x14388074
error TokenPreRedeemable(uint256 tokenId); //0x04df46e6
error ZeroEdition(); //0x2c0dcd39
error ZeroMintId(); //0x1ed046c6
error ZeroValue(); //0x7c946ed7
error ZeroTokenId(); //0x1fed7fc5


interface IC9Token {
    function getTokenParams(uint256 _tokenId) external view returns(uint256[18] memory params);
    function ownerOf(uint256 _tokenId) external view returns(address);
    function redeemAdd(uint256[] calldata _tokenId) external;
    function redeemCancel() external;
    function redeemFinish(uint256 _redeemerData) external;
    function redeemRemove(uint256[] calldata _tokenId) external;
    function redeemStart(uint256[] calldata _tokenId) external;
    function preRedeemable(uint256 _tokenId) external view returns(bool);
    function setTokenUpgraded(uint256 _tokenId) external;
    function setTokenValidity(uint256 _tokenId, uint256 _vId) external;
}

contract C9Token is IC9Token, C9Struct, ERC721, C9OwnerControl, IERC2981 {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
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
        uint256 indexed batchSize
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
        uint256 indexed batchSize
    );
    event RedemptionStart(
        address indexed tokenOwner,
        uint256 indexed batchSize
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
    constructor(uint256 _royaltyDefaultValue)
        ERC721("Collect9 NFTs", "C9T")
        limitRoyalty(_royaltyDefaultValue) {
            royaltyDefaultValue = uint96(_royaltyDefaultValue);
            royaltyDefaultReceiver = owner;
    }

    /*
     * @dev Checks if address is the same before update. There are 
     * a few functions that update addresses where this is used.
     */ 
    modifier addressNotSame(address _old, address _new) {
        if (_old == _new) {
            // _errMsg("address same");
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
            // _errMsg("caller must be contract");
            revert CallerNotContract();
        }
        _;
    }


    /*
     * @dev Checks to see if caller is the token owner.
     */ 
    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            // _errMsg("unauthorized");
            revert Unauthorized();
        }
        _;
    }

    /*
     * @dev Limits royalty inputs and updates to 10%.
     * Realistically there probably isn't a business model 
     * beyond 10%.
     */ 
    modifier limitRoyalty(uint256 _royalty) {
        if (_royalty > 999) {
            // _errMsg("royalty too high");
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
            // _errMsg("token is redeemed / dead");
            revert TokenIsDead(_tokenId);
        }
        _;
    }

    /*
     * @dev Checks to see if the tokenId exists.
     */
    modifier tokenExists(uint256 _tokenId) {
        if (!_exists(_tokenId)) {
            // _errMsg("non-existent token id");
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
            if (uint256(uint8(_tokenData>>POS_LOCKED)) == LOCKED) {
                // _errMsg("cannot xfer locked token");
                revert TokenIsLocked(tokenId);
            }
            // This will not happen often so _setTokenValidity is not being inlined
            if (uint256(uint8(_tokenData>>POS_VALIDITY)) == INACTIVE) {
                _setTokenValidity(tokenId, VALID);
            }
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Add IERC2981 for marketplaces to see EIP-2981.
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
                // _errMsg("royalty vals already set");
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
     * Cost: ~37,000 gas
     */
    function resetTokenRoyalty(uint256 _tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notDead(_tokenId)
        external {
            _setTokenRoyalty(_tokenId, royaltyDefaultReceiver, royaltyDefaultValue);
    }

    /**
     * @dev Receiver is royaltyDefaultReceiver(default is owner) unless 
     * otherwise specified in _rTokenData.
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
     * @dev Sets royalties due if token validity status 
     * is royalties. This is admin role instead of VALIDITY_ROLE 
     * to reduce gas costs. VALIDITY_ROLE will need to set 
     * validity status ROYALTIES before this can be set.
     * Cost: ~32,000 gas
     */
    function setRoyaltiesDue(uint256 _tokenId, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId) {
            if (_amount == 0) {
                // _errMsg("amount must be > 0");
                revert ZeroValue();
            }
            uint256 _tokenData = _uTokenData[_tokenId];
            uint256 _tokenValidity = uint256(uint8(_tokenData>>POS_VALIDITY));
            if (_tokenValidity != ROYALTIES) {
                // _errMsg("token status not royalties due");
                revert IncorrectTokenValidity(ROYALTIES, _tokenValidity);
            }
            if (uint256(uint16(_tokenData>>POS_ROYALTIESDUE)) == _amount) {
                // _errMsg("due amount already set");
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
     * Cost: ~31,000 gas
     */
    function setRoyaltyDefaultReceiver(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(royaltyDefaultReceiver, _address) {
            if (_address == address(0)) {
                // _errMsg("invalid address");
                revert ZeroAddressInvalid();
            }
            royaltyDefaultReceiver = _address;
    }

    /**
     * @dev Allows the contract owner to update the default royalties 
     * amount.
     * Cost: ~29,000 gas
     */
    function setRoyaltyDefaultValue(uint256 _royaltyDefaultValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_royaltyDefaultValue) {
            if (_royaltyDefaultValue == royaltyDefaultValue) {
                // _errMsg("royalty val already set");
                revert ValueAlreadySet();
            }
            royaltyDefaultValue = uint96(_royaltyDefaultValue);
    }

    /**
     * @dev Allows the contract owner to set royalties 
     * on a per token basis, within limits.
     * Note: set customRoyalty address to the null address 
     * to ignore it and use the already default set royalty address.
     * Cost:
     * Only royalty: ~37,000 gas
     * Only receiver: ~56,000 if rToken == address(0) else 39,000 subsequent 
     * Both at once: ~59,000 gas gas first time, 42,000 subsequent
     *
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
     * @dev Reduces revert error messages fee slightly. This will 
     * eventually be replaced by customErrors.
     */
    // function _errMsg(bytes memory message) 
    //     internal pure override {
    //         revert(string(bytes.concat("C9Token: ", message)));
    // }

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
                    _input.sData[0:_splitIndex]
                )
            );
    }

    /**
     * @dev Minting function. This checks and sets the `_edition` based on 
     * the `TokenData` input attributes, sets the `__mintId` based on 
     * the `_edition`, sets the royalty, and then stores all of the 
     * attributes required to construct the SVG in the tightly packed 
     * `TokenData` structure.
     *
     * Requirements:
     *
     * - `_input` royalty is <= 9.99%.
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
                __mintId == _input.mintid;
            }
            else {
                _mintId[_edition] = uint16(__mintId);
            }

            // Checks
            uint256 _tokenId = _input.tokenid;
            if (_tokenId == 0) {
                // _errMsg("token id cannot be 0");
                revert ZeroTokenId();
            }
            if (_edition == 0) {
                // _errMsg("edition cannot be 0");
                revert ZeroEdition();
            }
            if (_edition >= 99) {
                // _errMsg("edition overflow");
                revert EditionOverflow(_edition);
            }
            if (__mintId == 0) {
                // _errMsg("mint id cannot be 0");
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

    function _preRedeemable(uint256 _tokenData)
        private view
        returns (bool) {
            uint256 _ds = block.timestamp-uint256(uint40(_tokenData>>POS_MINTSTAMP));
            return _ds < preRedeemablePeriod;
    }

    /**
     * @dev
     * Updates the token validity status.
     * Validity will not prevent or pause transfers. It is 
     * only a display flag to let users know of the token's 
     * status.
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
                    type(uint8).max
                );
            }
            _uTokenData[_tokenId] = _tokenData;
    }

    /**
     * @dev Redeem cancel functions (either single token or 
     * batch) both call this to unlock the token.
     * Modifiers are placed here since _unlockToken is 
     * only called by RedeemCancel and RedeemFinish and 
     * its easier to enforce the modifier.
     */
    function _unlockToken(uint256 _tokenId)
        private
        isOwner(_tokenId) {
            uint256 _tokenData = _uTokenData[_tokenId];
            if (uint256(uint8(_tokenData>>POS_LOCKED)) == UNLOCKED) {
                // _errMsg("token not locked");
                revert TokenNotLocked(_tokenId);
            }
            // Unlock the token.
            _tokenData = _setTokenParam(
                _tokenData,
                POS_LOCKED,
                UNLOCKED,
                type(uint8).max
            );
            _uTokenData[_tokenId] = _tokenData;
    }

    /**
     * @dev The token burning required for the redemption process.
     * Require statement is the same as in ERC721Burnable.
     * Note the `tokenComboExists` of the token is not removed, thus 
     * once the `edition` of any burned token cannot be replaced, but 
     * instead will keep incrementing.
     * 
     * Requirements:
     *
     * - `tokenId` must exist.
     * - token burner must be token owner.
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
            // if (!confirm) _errMsg("burnAll not confirmed");
            if (!confirm) revert ActionNotConfirmed();
            uint256 ownerSupply = balanceOf(msg.sender);
            if (ownerSupply == 0) {
                // _errMsg("no tokens to burn");
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
            // if (!confirm) _errMsg("burnBatch not confirmed");
            if (!confirm) revert ActionNotConfirmed();
            uint256 _batchSize = _tokenId.length;
            if (_batchSize == 0) {
                // _errMsg("no tokens to burn");
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
     * @dev Returns list of contract this contract is linked to.
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
        external view
        override(C9Struct, IC9Token)
        returns(uint256[18] memory params) {
            uint256 _packedToken = _uTokenData[_tokenId];
            params[0] = uint256(uint8(_packedToken>>POS_UPGRADED));
            params[1] = uint256(uint8(_packedToken>>POS_DISPLAY));
            params[2] = uint256(uint8(_packedToken>>POS_LOCKED));
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
    }

    /**
     * @dev Helps makes the overall minting process faster and cheaper 
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

    /**
     * @dev To add to the interface.
     */
    function ownerOf(uint256 _tokenId)
        public view
        override(ERC721, IC9Token)
        returns (address) {
            return super.ownerOf(_tokenId);
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
                _tokenOwner = ownerOf(_tokenId);
                if (msg.sender != _tokenOwner) {
                    // _errMsg("unauthorized");
                    revert Unauthorized();
                }

                _tokenData = _uTokenData[_tokenId];
                if (_preRedeemable(_tokenData)) {
                    // _errMsg("token still pre-redeemable");
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
                        // _errMsg("token status not valid");
                        revert IncorrectTokenValidity(VALID, _validity);
                    }
                }

                // If valid and locked, can only be in redeemer.
                if (uint256(uint8(_tokenData>>POS_LOCKED)) == LOCKED) {
                    // _errMsg("token already in redeemer");
                    revert TokenIsLocked(_tokenId);
                }
                
                // Lock the token.
                _tokenData = _setTokenParam(
                   _tokenData,
                    POS_LOCKED,
                    LOCKED,
                    type(uint8).max
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
     * Note: While costs appear lower per token than the 
     * start process, the reported costs below ignore the 
     * initial start cost.
     */
    function redeemAdd(uint256[] calldata _tokenId)
        external override {
            _redeemLockTokens(_tokenId);
            IC9Redeemer(contractRedeemer).add(msg.sender, _tokenId);
            emit RedemptionAdd(msg.sender, _tokenId.length);
    }

    /**
     * @dev Allows user to cancel redemption process and resume 
     * token movement exchange capabilities.
     */
    function redeemCancel()
        external override {
            uint256 _redeemerData = IC9Redeemer(contractRedeemer).cancel(msg.sender);
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            uint256 _tokenId;
            for (uint256 i; i<_batchSize;) {
                _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
                _unlockToken(_tokenId);
                unchecked {
                    _tokenOffset += UINT_SIZE;
                    ++i;
                }
            }
            emit RedemptionCancel(msg.sender, _batchSize);
    }

    /**
     * @dev Redeemer contract calls and does a final lock on the token
     * after final admin approval.
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
                ownerOf(uint256(uint24(_redeemerData>>32))),
                _batchSize
            );
    }

    /**
     * @dev Allows user to remove specified tokens from 
     * an existing redemption process.
     * Note that this is quite a bit more expensive than 
     * canceling. Thus if a user plans to remove a 
     * majority of tokens then it may be cheaper to just 
     * cancel and restart.
     */
    function redeemRemove(uint256[] calldata _tokenId)
        external override {
            IC9Redeemer(contractRedeemer).remove(msg.sender, _tokenId);
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _unlockToken(_tokenId[i]);
                unchecked {++i;}
            }
            emit RedemptionRemove(msg.sender, _batchSize);
    }

    /**
     * @dev Starts the redemption process. Only the token holder can start.
     * Once started, the token is locked from further exchange. The user 
     * can still cancel the process before finishing.
     */
    function redeemStart(uint256[] calldata _tokenId)
        external override {
            _redeemLockTokens(_tokenId);
            IC9Redeemer(contractRedeemer).start(msg.sender, _tokenId);
            emit RedemptionStart(msg.sender, _tokenId.length);
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * This may be reduced in the future.
     * Cost: ~29,000 gas
     */
    function setPreRedeemPeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (preRedeemablePeriod == _period) {
                // _errMsg("period already set");
                revert ValueAlreadySet();
            }
            if (_period > 63113852) { // 2 years max
                // _errMsg("period too long");
                revert PeriodTooLong(63113852, _period);
            }
            preRedeemablePeriod = _period;
    }

    //>>>>>>> REDEEMER FUNCTIONS END

    //>>>>>>> SETTER FUNCTIONS START

    /**
     * @dev Updates the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork on IPFS, the 
     * contract will need to set the IPFS location.
     * Cost: ~48,000 gas first time, ~35,000 gas update, for ~32 length word.
     */
    function setBaseUri(string calldata _newBaseURI, uint256 _idx)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(_baseURI[_idx], _newBaseURI)) {
                // _errMsg("uri already set");
                revert URIAlreadySet();
                
            }
            bytes calldata _bBaseURI = bytes(_newBaseURI);
            uint256 len = _bBaseURI.length;
            if (bytes1(_bBaseURI[len-1]) != 0x2f) {
                // _errMsg("uri missing end slash");
                revert URIMissingEndSlash();
            }
            _baseURI[_idx] = _newBaseURI;
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     * Cost: ~29,000-46,000 gas depending on state
     */
    function setContractMeta(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractMeta, _address) {
            contractMeta = _address;
    }

    /**
     * @dev Updates the redemption contract address.
     * Cost: ~72,000 gas
     */
    function setContractRedeemer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractRedeemer, _address) {
            contractRedeemer = _address;
            _grantRole(REDEEMER_ROLE, contractRedeemer);
    }

    /**
     * @dev Updates the SVG display contract address.
     * This function will allow future SVG image display 
     * upgrades.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     * Cost: ~29,000-46,000 gas depending on state
     */
    function setContractSVG(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractSVG, _address) {
            contractSVG = _address;
    }

    /**
     * @dev Updates the upgrader contract address.
     * Cost: ~72,000 gas
     */
    function setContractUpgrader(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractUpgrader, _address) {
            contractUpgrader = _address;
            _grantRole(UPGRADER_ROLE, contractUpgrader);
    }

    /**
     * @dev Updates the contractURI.
     * Cost: ~35,000 gas for ~32 length word
     */
    function setContractURI(string calldata _newContractURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(_contractURI, _newContractURI)) {
                // _errMsg("uri already set");
                revert URIAlreadySet();
            }
            _contractURI = _newContractURI;
    }

    /**
     * @dev Updates the validity handler contract address.
     * Cost: ~72,000 gas
     */
    function setContractVH(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractVH, _address) {
            contractVH = _address;
            _grantRole(VALIDITY_ROLE, contractVH);
    }

    /**
     * @dev Set SVG flag to either display on-chain SVG (true) or IPFS 
     * version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     * Cost: ~46,000 gas for true, ~29,000 gas for false
     */
    function setSvgOnly(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (svgOnly == _flag) {
                // _errMsg("bool already set");
                revert BoolAlreadySet();
            }
            svgOnly = _flag;
    }

    /**
     * @dev Allows holder to set back to SVG view after 
     * token has already been upgraded. Flag must be set 
     * back to true for upgraded view to show again.
     * Cost: ~31,000 gas.
     */
    function setTokenDisplay(uint256 _tokenId, bool _flag)
        external
        isOwner(_tokenId) {
            uint256 _tokenData = _uTokenData[_tokenId];
            uint256 _val = uint256(uint8(_tokenData>>POS_UPGRADED));
            if (_val != 1) {
                // _errMsg("token is not upgraded");
                revert TokenNotUpgraded(_tokenId);
            }
            _val = uint256(uint8(_tokenData>>POS_DISPLAY));
            if (Helpers.uintToBool(_val) == _flag) {
                // _errMsg("view already set");
                revert BoolAlreadySet();
            }
            uint256 _display = _flag ? 1 : 0;
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_DISPLAY,
                _display,
                type(uint8).max
            );
    }

    /**
     * @dev Allows the compressed data that is used to display the 
     * micro QR code on the SVG to be updated. Each update costs 
     * around ~75,000 to ~100,000 gas based on the original 
     * minting data length.
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
     * Not allowed to set redeemed externally.
     * Cost: ~30,400 gas.
     */
    function setTokenValidity(uint256 _tokenId, uint256 _vId)
        external override
        onlyRole(VALIDITY_ROLE)
        isContract()
        tokenExists(_tokenId)
        notDead(_tokenId) {
            if (_vId == 4 || _vId == 5 || _vId > 8) {
                // _errMsg("invalid vId");
                revert InvalidVId(_vId);
            }
            uint256 _currentVId = uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY));
            if (_vId == _currentVId) {
                // _errMsg("vId already set");
                revert ValueAlreadySet();
            }
            _setTokenValidity(_tokenId, _vId);
    }

    /**
     * @dev Potential token upgrade path params.
     * Cost: ~31,000 gas.
     */
    function setTokenUpgraded(uint256 _tokenId)
        external override
        onlyRole(UPGRADER_ROLE)
        isContract()
        tokenExists(_tokenId)
        notDead(_tokenId) {
            uint256 _tokenData = _uTokenData[_tokenId];
            if (uint256(uint8(_tokenData>>POS_UPGRADED)) == 1) {
                // _errMsg("token already upgraded");
                revert TokenAlreadyUpgraded(_tokenId);
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_UPGRADED,
                UPGRADED,
                type(uint8).max
            );
    }

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in hmtl/xml code.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
    */
    function svgImage(uint256 _tokenId)
        public view
        tokenExists(_tokenId)
        returns (string memory) {
            return IC9SVG(contractSVG).returnSVG(
                ownerOf(_tokenId),
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
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Notes:
     * It seems like if the baseURI method fails after upgrade, OpenSea
     * still displays the cached on-chain version.
    */
    function tokenURI(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns (string memory) {
            uint256 _tokenData = _uTokenData[_tokenId];
            bool _externalView = uint256(uint8(_tokenData>>POS_DISPLAY)) == 1;
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
                uint256 _viewIdx = uint256(uint8(_tokenData>>POS_VALIDITY)) == REDEEMED ? 1 : 0;
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
     * @dev Allows batch transfer to make is cheaper to move multiple NFTs 
     * between two addresses. Batch size is limited to 32.
    */
    function transferFromBatch(address from, address to, uint256[] calldata _tokenId)
        external {
            uint256 _batchSize = _tokenId.length;
            if (_batchSize > 32) {
                // _errMsg("batchSize over 32");
                revert BatchSizeTooLarge(32, _batchSize);
            }
            for (uint256 i; i<_batchSize;) {
                transferFrom(from, to, _tokenId[i]);
                unchecked {++i;}
            }
    }

    /**
     * @dev Disables self-destruct functionality.
     * Other contracts like the registrar and redeemer 
     * that are upgradable also inherit but do not 
     * override this.
     * Note: even if admin gets through the confirm 
     * is hardcoded to false.
     */
    function __destroy(address _receiver, bool confirm)
        public override
        onlyRole(DEFAULT_ADMIN_ROLE) {
            confirm = false;
            super.__destroy(_receiver, confirm);
        }
}