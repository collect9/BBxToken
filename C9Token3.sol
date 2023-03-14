// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Struct4.sol";
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
    bool private _svgOnly;
    string[2] public _baseURIArray;

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
        _svgOnly = true;
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
        _isApprovedOrOwner(_msgSender(), ownerOf(tokenId), tokenId);
        _;
    }

    /*
     * @dev Checks to see the token is not dead. Any status redeemed 
     * or greater is a dead status, meaning the token is forever 
     * locked.
     */
    modifier notDead(uint256 tokenId) {
        if (_currentVId(_owners[tokenId]) >= REDEEMED) {
            revert TokenIsDead(tokenId);
        }
        _;
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
            MPOS_OWNER,
            uint256(0),
            type(uint160).max
        );
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

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function _getPhysicalHashFromTokenData(TokenData calldata input, uint256 edition)
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
        return _physicalHash(edition,
            input.cntrytag, input.cntrytush, input.gentag,
            input.gentush, input.markertush, input.special,
            input.sData[:_splitIndex]
        );
    }

    function _isLocked(uint256 _tokenData)
    private pure
    returns (bool) {
        return _tokenData & BOOL_MASK == LOCKED;
    }

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function _physicalHash(
        uint256 edition, uint256 cntrytag, uint256 cntrytush,
        uint256 gentag, uint256 gentush, uint256 markertush, 
        uint256 special, string calldata name
    )
    private pure
    returns (bytes32) {
        return keccak256(
            abi.encodePacked(edition, cntrytag, cntrytush,
                gentag, gentush, markertush, special, name
            )
        );
    }

    /*
     * @dev A lot of code has been repeated (inlined) here to minimize 
     * storage reads to reduce gas cost.
     */
    function _redeemLockTokens(uint256[] calldata _tokenIds)
    private {
        uint256 _batchSize = _tokenIds.length;
        uint256 _tokenId;
        uint256 _tokenData;
        for (uint256 i; i<_batchSize;) {
            _tokenId = _tokenIds[i];
            // 1. Check token exists and get owner
            // 2. Check caller is owner or approved to redeem
            _isApprovedOrOwner(_msgSender(), ownerOf(_tokenId), _tokenId);
            // 3. Check token is redeemable
            if (preRedeemable(_tokenId)) {
                revert TokenPreRedeemable(_tokenId);
            }
            // 4. Check the token validity status
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
            // 5. If valid but locked, token is already in redeemer
            if (_isLocked(_tokenData)) {
                revert TokenIsLocked(_tokenId);
            }
            // 6. All checks pass, so lock the token
            _tokenData = _setTokenParam(
                _tokenData,
                MPOS_LOCKED,
                LOCKED,
                BOOL_MASK
            );
            // 7. Save token data back to storage.
            _owners[_tokenId] = _tokenData;
            unchecked {++i;}
        }
    }

    /**
     * @dev Minting function. This checks and sets the `_edition` based on 
     * the `TokenData` input attributes, sets the `__mintId` based on 
     * the `_edition`, sets the royalty, and then stores all of the 
     * attributes required to construct the SVG in the tightly packed 
     * `TokenData` structure.
     */
    function _setTokenData(TokenData[] calldata input)
    private
    returns (uint256 votes) {
        uint256 timestamp = block.timestamp;
        uint256 batchSize = input.length;
        TokenData calldata _input;

        bytes32 _data;
        uint256 edition;
        uint256 editionMintId;
        uint256 tokenId;
        uint256 globalMintId = totalSupply();
        address to = _msgSender();
        uint256 _to = uint256(uint160(to));

        for (uint256 i; i<batchSize;) {
            _input = input[i];

            // Get physical edition id
            edition = _input.edition;
            if (edition == 0) {
                for (edition; edition<98;) {
                    unchecked {
                        ++edition;
                        _data = _getPhysicalHashFromTokenData(_input, edition);
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
            if (_exists(tokenId)) {
                revert TokenAlreadyMinted(tokenId);
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

            // Add to all tokens list
            _allTokens.push(uint24(tokenId));

            /* None of the values are big enough to overflow into the 
            next packed storage space, so the |= operation is fine when 
            done sequentially. */

            // _owners eXtended storage
            uint256 packedToken = _input.locked;
            packedToken |= _input.validity<<MPOS_VALIDITY;
            packedToken |= timestamp<<MPOS_VALIDITYSTAMP;
            packedToken |= _input.upgraded<<MPOS_UPGRADED;
            packedToken |= _input.display<<MPOS_DISPLAY;
            packedToken |= _input.insurance<<MPOS_INSURANCE;
            packedToken |= _input.votes<<MPOS_VOTES;
            packedToken |= _to<<MPOS_OWNER;
            _owners[tokenId] = packedToken; // Officially minted

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

            emit Transfer(address(0), to, tokenId);

            unchecked {
                ++i;
                votes += _input.votes;
            }
        }
        return votes;
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
     * @dev Allows the compressed data that is used to display the 
     * micro QR code on the SVG to be updated.
     */
    function _setTokenSData(uint256 tokenId, string calldata sData)
    private
    requireMinted(tokenId)
    notDead(tokenId) {
        _sTokenData[tokenId] = sData;
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
        if (!_isLocked(_tokenData)) {
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
    function adminUnlock(uint256 tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        requireMinted(tokenId)
        notDead(tokenId) {
            _unlockToken(tokenId);
    }

    /**
      Temp function testing only.
      */
    function baseURIArray(uint256 index)
        external view
        returns (string memory) {
            return _baseURIArray[index];
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
            // 2. Check the token has been dead for at least burnableDs
            uint256 _validityStamp = uint256(uint40(_tokenData>>MPOS_VALIDITYSTAMP));
            uint256 _ds = block.timestamp - _validityStamp;
            if (_ds < _burnableDs) {
                revert C9TokenNotBurnable(tokenId, validity);
            }
            
        }
        // Zero address burn
        _burn(tokenId);
        _setTokenValidity(tokenId, BURNED);
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
    function comboExists(
        uint256 cntrytag, uint256 cntrytush, uint256 gentag, 
        uint256 gentush, uint256 markertush, uint256 special, 
        string calldata name
    )
    external view
    returns (bool) {
        bytes32 _data = _physicalHash(1,
            cntrytag, cntrytush, gentag,
            gentush, markertush, special,
            name
        );
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
    returns(address meta, address redeemer, address svg, address upgrader, address vH) {
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
    returns(uint256[21] memory xParams) {
        // Data stored in owners
        uint256 data = _owners[tokenId];
        xParams[0] = uint256(uint24(data>>MPOS_XFER_COUNTER));
        xParams[1] = uint256(uint40(data>>MPOS_VALIDITYSTAMP));
        xParams[2] = _currentVId(data);
        xParams[3] = data>>MPOS_UPGRADED & BOOL_MASK;
        xParams[4] = data>>MPOS_DISPLAY & BOOL_MASK;
        xParams[5] = data>>MPOS_LOCKED & BOOL_MASK;
        xParams[6] = _viewPackedData(data, MPOS_INSURANCE, MSZ_INSURANCE);
        xParams[7] = _viewPackedData(data, MPOS_VOTES, MSZ_VOTES);
        // Data stored in uTokenData
        data = _uTokenData[tokenId];
        xParams[8] = uint256(uint16(data>>UPOS_GLOBAL_MINT_ID)); // Global Mint Id
        xParams[9] = uint256(uint40(data>>UPOS_MINTSTAMP));
        xParams[10] = _viewPackedData(data, UPOS_EDITION, USZ_EDITION);
        xParams[11] = uint256(uint16(data>>UPOS_EDITION_MINT_ID));
        xParams[12] = _viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG);
        xParams[13] = _viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH);
        xParams[14] = _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG);
        xParams[15] = _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH);
        xParams[16] = _viewPackedData(data, UPOS_MARKERTUSH, USZ_MARKERTUSH);
        xParams[17] = _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL);
        xParams[18] = _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER);
        xParams[19] = _viewPackedData(data, UPOS_ROYALTY, USZ_ROYALTY);
        xParams[20] = _viewPackedData(data, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE);
    }

    /* @dev Batch minting function.
     */
    function mint(TokenData[] calldata input)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 votes = _setTokenData(input);

        // Update minter balance
        (uint256 minterBalance, uint256 minterVotes,,) = ownerDataOf(_msgSender());
        unchecked {
            minterBalance += input.length;
            minterVotes += votes;
        }
        uint256 balances = _balances[_msgSender()];
        balances &= ~(MASK_BALANCER)<<APOS_BALANCE;
        balances |= minterBalance<<APOS_BALANCE;
        balances |= minterVotes<<APOS_VOTES;
        _balances[_msgSender()] = balances;
    }

    //>>>>>>> REDEEMER FUNCTIONS START

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
        address tokenOwner = _ownerOf(_tokenIds[0]);
        IC9Redeemer(contractRedeemer).add(tokenOwner, _tokenIds);
    }

    /**
     * @dev Allows user to cancel redemption process and 
     * unlock all tokens. The tokenIds come back from the 
     * redeemer in the form of packed data that is 
     * [batchsize, tokenId1, tokenId2, ...]
     */
    function redeemCancel()
    external {
        uint256 _redeemerData = IC9Redeemer(contractRedeemer).cancel(_msgSender());
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
    }

    /**
     * @dev Finishes redemption. Called by the redeemer contract.
     */
    function redeemFinish(uint256 redeemerData)
    external
    onlyRole(REDEEMER_ROLE)
    isContract() {
        uint256 _batchSize = uint256(uint8(redeemerData>>RPOS_BATCHSIZE));
        uint256 _tokenOffset = RPOS_TOKEN1;
        uint256 _tokenId;
        // Set all tokens to redeemed
        for (uint256 i; i<_batchSize;) {
            _tokenId = uint256(uint24(redeemerData>>_tokenOffset));
            _setTokenValidity(_tokenId, REDEEMED);
            unchecked {
                _tokenOffset += UINT_SIZE;
                ++i;
            }
        }
        // Update the redeemer's redemption count
        _addRedemptions(ownerOf(_tokenId), _batchSize);
    }

    /**
     * @dev Allows user to remove tokens from 
     * an existing redemption process.
     */
    function redeemRemove(uint256[] calldata tokenIds)
    external {
        uint256 _batchSize = tokenIds.length;
        uint256 _tokenId;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            _isApprovedOrOwner(_msgSender(), ownerOf(_tokenId), _tokenId);
            _unlockToken(_tokenId);
            unchecked {++i;}
        }
        IC9Redeemer(contractRedeemer).remove(_msgSender(), tokenIds);
    }

    /**
     * @dev Starts the redemption process.
     * Once started, the token is locked from further exchange 
     * unless canceled.
     */
    function redeemStart(uint256[] calldata tokenIds)
    external {
        _redeemLockTokens(tokenIds);
        address tokenOwner = _ownerOf(tokenIds[0]);
        IC9Redeemer(contractRedeemer).start(tokenOwner, tokenIds);
    }

    //>>>>>>> REDEEMER FUNCTIONS END

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
        if (Helpers.stringEqual(_baseURIArray[_idx], _newBaseURI)) {
            revert URIAlreadySet();
        }
        bytes calldata _bBaseURI = bytes(_newBaseURI);
        uint256 len = _bBaseURI.length;
        if (bytes1(_bBaseURI[len-1]) != 0x2f) {
            revert URIMissingEndSlash();
        }
        _baseURIArray[_idx] = _newBaseURI;
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
     */
    function setBurnablePeriod(uint256 period)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (period > MAX_PERIOD) {
            revert PeriodTooLong(MAX_PERIOD, period);
        }
        if (_burnableDs == period) {
            revert ValueAlreadySet();
        }
        _burnableDs = period;
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
        _grantRole(REDEEMER_ROLE, _address);
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
        _grantRole(UPGRADER_ROLE, _address);
    }

    /**
     * @dev Sets the contractURI.
     */
    function setContractURI(string calldata newContractURI)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (Helpers.stringEqual(_contractURI, newContractURI)) {
            revert URIAlreadySet();
        }
        _contractURI = newContractURI;
    }

    /**
     * @dev Sets the validity handler contract address.
     */
    function setContractVH(address _address)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    addressNotSame(contractVH, _address) {
        contractVH = _address;
        _grantRole(VALIDITY_ROLE, _address);
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     * Limit hardcoded.
     */
    function setPreRedeemPeriod(uint256 period)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (period > MAX_PERIOD) {
            revert PeriodTooLong(MAX_PERIOD, period);
        }
        if (_preRedeemablePeriod == period) {
            revert ValueAlreadySet();
        }
        _preRedeemablePeriod = period;
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
    requireMinted(tokenId)
    notDead(tokenId) {
        if (amount == 0) {
            revert ZeroValueError();
        }
        uint256 _tokenValidity = _currentVId(_owners[tokenId]);
        if (_tokenValidity != ROYALTIES) {
            revert IncorrectTokenValidity(ROYALTIES, _tokenValidity);
        }
        uint256 _tokenData = _uTokenData[tokenId];
        if (_viewPackedData(_tokenData, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE) == amount) {
            revert RoyaltiesAlreadySet();
        }
        _uTokenData[tokenId] = _setTokenParam(
            _tokenData,
            UPOS_ROYALTIES_DUE,
            amount,
            MASK_ROYALTIES_DUE
        );
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
    notDead(tokenId) {
        if (royalty > 999) {
            revert RoyaltyTooHigh();
        }
        _setTokenRoyalty(tokenId, receiver, royalty);
    }

    /**
     * @dev Allows the compressed data that is used to display the 
     * micro QR code on the SVG to be updated.
     */
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
    //onlyRole(VALIDITY_ROLE)
    //isContract()
    requireMinted(tokenId) {
        if (vId >= REDEEMED) {
            revert TokenIsDead(tokenId);
        }
        if (vId == _currentVId(_owners[tokenId])) {
            revert ValueAlreadySet();
        }
        _setTokenValidity(tokenId, vId);
    }

    /**
     * @dev Sets the token as upgraded.
     */
    function setTokenUpgraded(uint256 tokenId)
    external
    //onlyRole(UPGRADER_ROLE)
    //isContract()
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
     * @dev Set SVG flag to either display on-chain SVG (true) or  
     * external version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     */
    function toggleSvgOnly(bool toggle)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_svgOnly == toggle) {
            revert BoolAlreadySet();
        }
        _svgOnly = toggle;
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
    public view
    override(ERC721)
    requireMinted(_tokenId)
    returns (string memory) {
        uint256 _tokenData = _owners[_tokenId];
        bool _externalView = (_tokenData>>MPOS_DISPLAY & BOOL_MASK) == EXTERNAL_IMG;
        bytes memory image;
        if (_svgOnly || !_externalView) {
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
                _baseURIArray[_viewIdx],
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
        //confirm = false;
        super.__destroy(_receiver, confirm);
    }

    /**
     * @dev Sets the data for the reserved (unused at mint) 
     * space. Since this storage is already paid for, it may
     * be used for expansion features that may be available 
     * later. Such features will only be available to 
     * external contracts, as this contract will have no
     * built-in parsing.
     * 120 bits remain in the reserved storage space.
     */
    function _setReserved(uint256 tokenId, uint256 data)
    private
    isOwnerOrApproved(tokenId) {
        _uTokenData[tokenId] = _setTokenParam(
            _uTokenData[tokenId],
            UPOS_RESERVED,
            data,
            type(uint120).max
        );
    }

    /**
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function setReserved(uint256[2][] calldata data)
    external {
        if (!_reservedOpen) {
            revert ReservedSpaceNotOpen();
        }
        uint256 _batchSize = data.length;
        for (uint256 i; i<_batchSize;) {
            _setReserved(data[i][0], data[i][1]);
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