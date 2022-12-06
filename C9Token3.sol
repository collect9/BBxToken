// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;
import "./utils/ERC721Enum32packed.sol";

//import "./C9MetaData.sol";
import "./C9OwnerControl.sol";
import "./C9Redeemer24.sol";
import "./C9Struct2.sol";
import "./C9SVG2.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";

interface IC9Token {
    function getTokenParams(uint256 _tokenId) external view returns(uint256[18] memory params);
    function redeemAdd(uint256[] calldata _tokenId) external;
    function redeemCancel() external;
    function redeemFinish(uint256 _redeemerData) external;
    function redeemRemove(uint256[] calldata _tokenId) external;
    function redeemStart(uint256[] calldata _tokenId) external;
    function preRedeemable(uint256 _tokenId) external view returns(bool);
    function setTokenUpgraded(uint256 _tokenId, uint256 _val) external;
}

contract C9Token is IC9Token, C9Struct, ERC721Enumerable, C9OwnerControl {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Default royalty. These should be packed into one slot.
     */
    address public royaltyDefaultReceiver;
    uint96 public royaltyDefaultValue;

    /**
     * @dev The meta and SVG contracts that this token contract
     * interact with.
     */
    address public contractMeta;
    address public contractRedeemer;
    address public contractSVG;

    /**
     * @dev Flag that may enable external artwork versions to be 
     * displayed in the future.
     */
    bool public svgOnly = true;
    string[2] private __baseURI;

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI = "collect9.io/metadata/C9BBxToken";

    /**
     * @dev Redemption definitions and events. preRedeem period 
     * defines how long a token must exist before it can be 
     * redeemed.
     */
    uint256 public preRedeemablePeriod = 31556926; //seconds
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
     * @dev Structure that holds all of the token info required to 
     * construct the 100% on chain SVG.
     * The properties within _uTokenData that define 
     * the physical collectible cannot be modified once set.
     */
    mapping(uint256 => address) private _rTokenData;
    mapping(uint256 => uint256) private _uTokenData;
    mapping(uint256 => string) private _sTokenData;
    
    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenData has already been minted. The boolean determines
     * whether or not to increment the editionID.
     */
    mapping(bytes32 => bool) private _tokenComboExists;

    /**
     * @dev _mintId stores the minting ID number for up to 99 editions.
     * This means that 96 of some physical collectible, differentiated 
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
            _errMsg("address same");
        }
        _;
    }

    /*
     * @dev Checks to see whether or not the token is in the 
     * redemption process.
     */ 
    modifier inRedemption(uint256 _tokenId, uint256 status) {
        uint256 _tokenData = _uTokenData[_tokenId];
        if (uint256(uint8(_tokenData>>POS_VALIDITY)) == REDEEMED) {
            _errMsg("token is redeemed");
        }
        if (uint256(uint8(_tokenData>>POS_LOCKED)) != status) {
            _errMsg("redemption status disallows");
        }
        _;
    }

    /*
     * @dev Checks to see if caller is the token owner.
     */ 
    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            _errMsg("unauthorized");
        }
        _checkActivity(_tokenId);
        _;
    }

    /*
     * @dev Limits royalty inputs to 10%.
     */ 
    modifier limitRoyalty(uint256 _royalty) {
        if (_royalty > 999) {
            _errMsg("royalty too high");
        }
        _;
    }

    /*
     * @dev Checks to see the token is not yet redeemed. This is a 
     * bit redundant to inRedemption, however some things like 
     * updating royalties should not depend on the token being 
     * outside of the redemption process.
     */ 
    modifier notRedeemed(uint256 _tokenId) {
        if (uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY)) == REDEEMED) {
            _errMsg("token is redeemed");
        }
        _;
    }

    /*
     * @dev Checks to see the token exists.
     */
    modifier tokenExists(uint256 _tokenId) {
        if (!_exists(_tokenId)) {
            _errMsg("non-existent token id");
        }
        _;
    }

    /**
     * @dev Required overrides from imported contracts.
     */
    function _baseURI() internal view override returns(string memory) {
        return __baseURI[0];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
        )
        internal
        override(ERC721Enumerable)
        notFrozen()
        inRedemption(tokenId, 0) {
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
            _checkActivity(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view
        override(ERC721Enumerable, AccessControl)
        returns (bool) {
            return super.supportsInterface(interfaceId);
    }

    //>>>>>>> CUSTOM ERC2981 START

    /*
     * @dev Since royalty info is already stored in the uTokenData,
     * we don't need a new slots for per token royalties as is defined 
     * in the ERC2981 standard. This custom implementation that reads 
     * and updates uTokenData saves a good chunk of gas.
     */
    function _setTokenRoyalty(uint256 _tokenId, address _receiver, uint256 _royalty)
        internal {
            (address _royaltyAddress, uint256 _royaltyAmt) = royaltyInfo(_tokenId, 10000);
            bool _newReceiver = _receiver != _royaltyAddress;
            bool _newRoyalty = _royalty != _royaltyAmt;
            if (!_newReceiver && !_newRoyalty) {
                _errMsg("royalty vals already set");
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
                    65535
                );
            }
    }

    /**
     * @dev Resets royalty information for the token id back to the 
     * global default.
     * Cost: ~37,000 gas
     */
    function resetTokenRoyalty(uint256 _tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
        external {
            _setTokenRoyalty(_tokenId, royaltyDefaultReceiver, royaltyDefaultValue);
    }

    /**
     * @dev Receiver is royaltyDefaultReceiver(default is owner) unless 
     * otherwise specified for that tokenId.
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        public view
        returns (address, uint256) {
            address receiver = _rTokenData[_tokenId];
            if (receiver == address(0)) {
                receiver = royaltyDefaultReceiver;
            }
            uint256 _fraction = uint256(uint16(_uTokenData[_tokenId]>>POS_ROYALTY));
            uint256 royaltyAmount = (_salePrice * _fraction) / 10000;
            return (receiver, royaltyAmount);
    }

    /**
     * @dev Sets royalties due if token validity status 
     * is royalties.
     * Cost: ~32,000 gas
     */
    function setRoyaltiesDue(uint256 _tokenId, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId) {
            if (_amount == 0) {
                _errMsg("amount must be > 0");
            }
            uint256 _tokenData = _uTokenData[_tokenId];
            if (uint256(uint8(_tokenData>>POS_VALIDITY)) != ROYALTIES) {
                _errMsg("token status not royalties due");
            }
            if (uint256(uint16(_tokenData>>POS_ROYALTIESDUE)) == _amount) {
                _errMsg("due amount already set");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_ROYALTIESDUE,
                _amount,
                65535
            );
    }

    /**
     * @dev Allows contract to have a separate royalties receiver 
     * address. The default receiver is owner.
     * Cost: ~31,000 gas
     */
    function setRoyaltyDefaultReceiver(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(royaltyDefaultReceiver, _address) {
            if (_address == address(0)) {
                _errMsg("invalid address");
            }
            royaltyDefaultReceiver = _address;
    }

    /**
     * @dev Allows the contract owner to update the global royalties 
     * recever address and amount.
     * Cost: ~29,000 gas
     */
    function setRoyaltyDefaultValue(uint256 _royaltyDefaultValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_royaltyDefaultValue) {
            if (_royaltyDefaultValue == royaltyDefaultValue) {
                _errMsg("royalty val already set");
            }
            royaltyDefaultValue = uint96(_royaltyDefaultValue);
    }

    //>>>>>>> CUSTOM ERC2981 END

    /**
     * @dev This function is meant to automatically fix an inactive 
     * validity status when the owner interacts with the contract.
     * It is placed _beforeTokenTransfer and in the isOwner modifier.
     */
    function _checkActivity(uint256 _tokenId)
        internal {
            if (uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY)) == INACTIVE) {
                _setTokenValidity(_tokenId, VALID);
            }
    }

    /**
     * @dev Reduces revert error messages fee slightly. This will 
     * eventually be replaced by customError when Ganache 
     * supports them.
     */
    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Token: ", message)));
    }

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function _getPhysicalHash(TokenData calldata _input, uint256 _edition)
        internal pure
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
     * @dev The function that start the redeemer (either single token
     * or batch) both call this to lock the token. Since both call this 
     * right away, the modifiers are here.
     *
     * Requirements:
     * 1. Caller must be token owner
     * 2. Token must not already be in redemption process or redeemed
     */
    function _lockToken(uint256 _tokenId)
        internal
        isOwner(_tokenId)
        inRedemption(_tokenId, 0) {
            if (uint256(uint8(_uTokenData[_tokenId]>>POS_VALIDITY)) != VALID) {
                _errMsg("token status not valid");
            }
            if (preRedeemable(_tokenId)) {
                _errMsg("token still pre-redeemable");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_LOCKED,
                1,
                255
            );
    }

    /**
     * @dev Once the token validity is set to 4, it is 
     * not possible to change it back. Only the redemption 
     * finisher functions call this.
     */
    function _setTokenRedeemed(uint256 _tokenId)
        internal
        tokenExists(_tokenId)
        inRedemption(_tokenId, 1) {
            _setTokenValidity(_tokenId, REDEEMED);
    }

    /**
     * @dev
     * Updates the token validity status.
     * Validity will not prevent or pause transfers. It is 
     * only a display flag to let users know of the token's 
     * status.
     */
    function _setTokenValidity(uint256 _tokenId, uint256 _vId)
        internal
        notRedeemed(_tokenId) {
            if (_vId > 4) {
                _errMsg("invalid internal vId");
            }
            uint256 _tokenData = _uTokenData[_tokenId];
            uint256 _tokenValidity = uint256(uint8(_tokenData>>POS_VALIDITY));
            if (_tokenValidity == _vId) {
                _errMsg("vId already set");
            }
            _tokenData = _setTokenParam(
                _tokenData,
                POS_VALIDITY,
                _vId,
                255
            );
            _tokenData = _setTokenParam(
                _tokenData,
                POS_VALIDITYSTAMP,
                block.timestamp,
                1099511627775
            );
            _uTokenData[_tokenId] = _tokenData;
    }

    /**
     * @dev Redeem cancel functions (either single token or 
     * batch) both call this to unlock the token.
     *
     * Requirements:
     * 1. Caller must be owner
     * 2. Token must be in the redemption process (not redeemed)
     */
    function _unlockToken(uint256 _tokenId)
        internal
        isOwner(_tokenId)
        inRedemption(_tokenId, 1) {
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_LOCKED,
                0,
                255
            );
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
    function burnAll()
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 totalSupply = totalSupply();
            for (uint256 i; i<totalSupply;) {
                burn(tokenByIndex(0));
                unchecked {++i;}
            }
    }

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in html/xml code.
    */
    function b64SVGImage(uint256 _tokenId)
        internal view
        returns (string memory) {
            return Base64.encode(bytes(svgImage(_tokenId)));
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
     * @dev uTokenData is packed into a single uint256. This function
     * returns an unpacked array. It overrides the C9Struct defintion 
     * so only the _tokenId needs to be passed in.
     */
    function getTokenParams(uint256 _tokenId)
        public view
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
    function mint1(TokenData calldata _input)
        internal
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
            uint256 __mintId = _mintId[_edition]+1;
            if (_input.mintid != 0) {
                __mintId == _input.mintid;
            }
            else {
                _mintId[_edition] = uint16(__mintId);
            }

            // Checks
            uint256 _tokenId = _input.tokenid;
            if (_tokenId == 0) {
                _errMsg("token id cannot be 0");
            }
            if (_edition == 0) {
                _errMsg("edition cannot be 0");
            }
            if (_edition >= 99) {
                _errMsg("edition overflow");
            }
            if (__mintId == 0) {
                _errMsg("mint id cannot be 0");
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
     * @dev Helps makes the overall minting process faster and cheaper 
     * on average per mint.
    */
    function mintBatch(TokenData[] calldata _input)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _input.length;
            for (uint256 i; i<_batchSize;) {
                mint1(_input[i]);
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
            uint256 _ds = block.timestamp-uint256(uint40(_uTokenData[_tokenId]>>POS_MINTSTAMP));
            return _ds < preRedeemablePeriod;
    }

    //>>>>>>> REDEEMER FUNCTIONS START

    /**
     * @dev Add tokens to an existing redemption process.
     * Once added, the token is locked from further exchange until 
     * either canceled or removed.
     * Note: While costs appear lower per token than the 
     * start process, the reported costs below ignore the 
     * initial start cost.
     * Cost:
     * 1x token = 54,800 gas
     * 2x token = 64,500 gas
     * 5x token = 93,330 gas
     * 6x token = 102,700 gas
     * 8x token = 122,200 gas 
     */
    function redeemAdd(uint256[] calldata _tokenId)
        external override {
            IC9Redeemer(contractRedeemer).add(msg.sender, _tokenId);
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _lockToken(_tokenId[i]);
                unchecked {++i;} //checked in IC9Redeemer
            }
            emit RedemptionAdd(msg.sender, _batchSize);
    }

    /**
     * @dev Allows user to cancel redemption process and resume 
     * token movement exchange capabilities.
     * Cost:
     * 1x token = 42,200 gas
     * 2x token = 50,400 gas
     * 6x token = 83,200 gas
     * 7x token = 91,400 gas
     * 9x token = 107,800 gas
     */
    function redeemCancel()
        external override {
            uint256 _redeemerData = IC9Redeemer(contractRedeemer).cancel(msg.sender);
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _unlockToken(uint256(uint24(_redeemerData>>_tokenOffset)));
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
        onlyRole(REDEEMER_ROLE) {
            uint256 _batchSize = uint256(uint8(_redeemerData>>RPOS_BATCHSIZE));
            uint256 _tokenOffset = RPOS_TOKEN1;
            for (uint256 i; i<_batchSize;) {
                _setTokenRedeemed(uint256(uint24(_redeemerData>>_tokenOffset)));
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
     * Cost:
     * 1x token = 50,200 gas
     * 5x token = 86,500 gas
     * 6x token = 96,000 gas
     * 9x token = 116,800 gas
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
     * Cost:
     * 1x token = 83,100 gas
     * 2x token = 92,500 gas
     * 6x token = 130,300 gas
     * 7x token = 139,700 gas
     * 9x token = 158,600 gas
     */
    function redeemStart(uint256[] calldata _tokenId)
        external override {
            IC9Redeemer(contractRedeemer).start(msg.sender, _tokenId);
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _lockToken(_tokenId[i]);
                unchecked {++i;}
            }
            
            emit RedemptionStart(msg.sender, _batchSize);
    }

    //>>>>>>> REDEEMER FUNCTIONS END

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
            if (Helpers.stringEqual(__baseURI[_idx], _newBaseURI)) {
                _errMsg("uri already set");
            }
            bytes calldata _bBaseURI = bytes(_newBaseURI);
            uint256 len = _bBaseURI.length;
            if (bytes1(_bBaseURI[len-1]) != 0x2f) {
                _errMsg("uri missing end slash");
            }
            __baseURI[_idx] = _newBaseURI;
    }

     /**
     * @dev Updates the contractURI.
     * Cost: ~35,000 gas for ~32 length word
     */
    function setContractUri(string calldata _newContractURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(_contractURI, _newContractURI)) {
                _errMsg("uri already set");
            }
            _contractURI = _newContractURI;
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
     * @dev Updates the redemption data contract address.
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
     * @dev Gets or sets the global token redeemable period.
     * This may be reduced in the future.
     * Cost: ~29,000 gas
     */
    function setPreRedeemPeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (preRedeemablePeriod == _period) {
                _errMsg("period already set");
            }
            if (_period > 63113852) { // 2 years max
                _errMsg("period too long");
            }
            preRedeemablePeriod = _period;
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
        tokenExists(_tokenId) {
            _sTokenData[_tokenId] = _sData;
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
                _errMsg("bool already set");
            }
            svgOnly = _flag;
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
        limitRoyalty(_newRoyalty)
        tokenExists(_tokenId)
        notRedeemed(_tokenId) {
            _setTokenRoyalty(_tokenId, _receiver, _newRoyalty);
    }

    /*
     * @dev Sets the token validity.
     * Cost: ~33,500 gas.
     */
    function setTokenValidity(uint256 _tokenId, uint256 _vId)
        external
        onlyRole(VALIDITY_ROLE)
        tokenExists(_tokenId) {
            if (_vId > 3) {
                _errMsg("invalid external vId");
            }
            _setTokenValidity(_tokenId, _vId);
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
                _errMsg("token is not upgraded");
            }
            _val = uint256(uint8(_tokenData>>POS_DISPLAY));
            if (Helpers.uintToBool(_val) == _flag) {
                _errMsg("view already set");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_DISPLAY,
                _flag ? 1 : 0,
                255
            );
    }

    /**
     * @dev Potential token upgrade path params.
     * Cost: ~31,000 gas.
     */
    function setTokenUpgraded(uint256 _tokenId, uint256 _val)
        external override
        onlyRole(UPGRADER_ROLE)
        tokenExists(_tokenId) {
            if (_val == 0 || _val > 9) {
                _errMsg("invalid upgrade val");
            }
            uint256 _tokenData = _uTokenData[_tokenId];
            if (uint256(uint8(_tokenData>>POS_UPGRADED)) == _val) {
                _errMsg("token is already upgraded");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _tokenData,
                POS_UPGRADED,
                _val,
                255
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
                    b64SVGImage(_tokenId)
                );
            }
            else {
                // Token upgraded, get view URI based on if redeemed or not
                uint256 _viewIdx = uint256(uint8(_tokenData>>POS_VALIDITY)) == REDEEMED ? 1 : 0;
                image = abi.encodePacked(
                    ',"image":"',
                    __baseURI[_viewIdx],
                    _tokenId,
                    '.png'
                );
            }
            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            //IC9MetaData(contractMeta).metaNameDesc(_tokenData, _sTokenData[_tokenId][0]),
                            image
                            //IC9MetaData(contractMeta).metaAttributes(_tokenData)
                        )
                    )
                )
            );
    }

    /**
     * @dev Disables self-destruct functionality.
     * Other contracts like the registrar and redeemer 
     * that are upgradable also inherit but do not 
     * override this.
     */
    function __destroy(address _receiver, bool confirm)
        public override
        onlyRole(DEFAULT_ADMIN_ROLE) {
            confirm = false;
            super.__destroy(_receiver, confirm);
        }
}