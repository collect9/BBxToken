// SPDX-License-Identifier: MIT
pragma solidity >0.8.17;
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG2.sol";
import "./interfaces/IC9Redeemer24.sol";
import "./interfaces/IC9Token.sol";
import "./utils/Helpers.sol";


import "./utils/C9ERC721EnumBasic.sol";

contract C9Token is ERC721IdEnumBasic {
    /**
     * @dev https://docs.opensea.io/docs/metadata-standards.
     * While there is no definitive EIP yet for token staking or locking, OpenSea 
     * does support several events to help signal that a token should not be eligible 
     * for trading. This helps prevent "execution reverted" errors for your users 
     * if transfers are disabled while in a staked or locked state.
     */
    event TokenLocked(uint256 indexed tokenId, address indexed approvedContract);
    event TokenUnlocked(uint256 indexed tokenId, address indexed approvedContract);

    /**
     * @dev Contract access roles.
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant UPDATER_ROLE  = keccak256("UPDATER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Contracts this token contract interacts with.
     */
    address private contractMeta;
    address private contractRedeemer;
    address private contractUpgrader;
    address private contractVH;

    /**
     * @dev Flag that may enable external (IPFS) artwork 
     * versions to be displayed in the future. The _baseURI
     * is a string[2]: index 0 is active and index 1 is 
     * for inactive.
     */
    bool private _svgOnly;
    string[2] private _baseURIArray;

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
    uint24[] private _burnedTokens;
    uint256 private _preRedeemablePeriod; //seconds
    uint24[] private _redeemedTokens;
    
    /**
     * @dev Mappings that hold all of the token info required to 
     * construct the 100% on chain SVG.
     * Many properties within _uTokenData that define 
     * the physical collectible are immutable by design.
     */
    mapping(uint256 => address) private _rTokenData;
    mapping(uint256 => uint256) private _cTokenData;
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
        emit Transfer(ownerOf(tokenId), address(0), tokenId);
        delete _tokenApprovals[tokenId];
        // Set zero address
        _owners[tokenId] = _setTokenParam(
            _owners[tokenId],
            MPOS_OWNER,
            uint256(0),
            type(uint160).max
        );
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * The IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup.
     */
    function _isRedeemable(uint256 tokenId, uint256 tokenData)
    private view
    returns (bool) {
        if (_preRedeemable(_uTokenData[tokenId])) {
            return false;
        }
        uint256 _vId = _currentVId(tokenData); 
        if (_vId != VALID) {
            if (_vId != INACTIVE) {
                return false;
            }
        }
        return true;
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

    /**
     * @dev Returns whether or not the token pre-release period 
     * has ended.
     */
    function _preRedeemable(uint256 tokenData)
    private view
    returns (bool) {
        uint256 _ds = block.timestamp - _viewPackedData(tokenData, UPOS_MINTSTAMP, USZ_TIMESTAMP);
        return _ds < _preRedeemablePeriod;
    }

    /*
     * @dev The function that locks to token prior to 
     * calling the redeemer contract.
     */
    function _redeemLockTokens(uint256[] calldata _tokenIds)
    private {
        uint256 _batchSize = _tokenIds.length;
        uint256 _tokenId;
        uint256 _tokenData;
        for (uint256 i; i<_batchSize;) {
            _tokenId = _tokenIds[i];
            // 1. Check token exists (implicit via ownerOf()) and that caller is owner or approved
            _isApprovedOrOwner(_msgSender(), ownerOf(_tokenId), _tokenId);
            // 2. Copy token data from storage
            _tokenData = _owners[_tokenId];
            // 3. Check token is redeemable
            if (!_isRedeemable(_tokenId, _tokenData)) {
                revert TokenNotRedeemable(_tokenId);
            }
            /* 4. If redeemable but locked, token is already in redeemer.
                  This will also prevent multiple approved trying to
                  redeem the same token at once.
            */
            if (_tokenData & BOOL_MASK == LOCKED) {
                revert TokenIsLocked(_tokenId);
            }
            // 5. All checks pass, so lock the token
            _tokenData = _lockToken(_tokenId, _tokenData);
            // 6. Save to storage
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
                        _data = _physicalHash(edition,
                            _input.cntrytag, _input.cntrytush, _input.gentag,
                            _input.gentush, _input.markertush, _input.special,
                            _input.name);
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
            if (edition > 99) {
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
            packedToken |= _input.royalty<<MPOS_ROYALTY;
            packedToken |= _input.votes<<MPOS_VOTES;
            packedToken |= _to<<MPOS_OWNER;
            _owners[tokenId] = packedToken; // Officially minted
            
            // Additional storage in _uTokenData
            packedToken = timestamp;
            packedToken |= edition<<UPOS_EDITION;
            packedToken |= editionMintId<<UPOS_EDITION_MINT_ID;
            packedToken |= _input.cntrytag<<UPOS_CNTRYTAG;
            packedToken |= _input.cntrytush<<UPOS_CNTRYTUSH;
            packedToken |= _input.gentag<<UPOS_GENTAG;
            packedToken |= _input.gentush<<UPOS_GENTUSH;
            packedToken |= _input.markertush<<UPOS_MARKERTUSH;
            packedToken |= _input.special<<UPOS_SPECIAL;
            packedToken |= _input.raritytier<<UPOS_RARITYTIER;
            packedToken |= uint256(uint152(bytes19(bytes(_input.name))))<<UPOS_NAME;
            
            packedToken |= _input.royaltiesdue<<UPOS_ROYALTIES_DUE;
            _uTokenData[tokenId] = packedToken;

            // Store token data for SVG
            _cTokenData[tokenId] = _input.cData;

            emit Transfer(address(0), to, tokenId);

            unchecked {
                ++i;
                votes += _input.votes;
            }
        }
        return votes;
    }

    function _lockToken(uint256 tokenId, uint256 tokenData)
    private
    returns (uint256) {
        emit TokenLocked(tokenId, address(this));
        return _setTokenParam(
            tokenData,
            MPOS_LOCKED,
            LOCKED,
            BOOL_MASK
        );
    }

    /**
     * @dev Updates the token validity status.
     */
    function _setTokenValidity(uint256 tokenId, uint256 vId)
    private {
        uint256 tokenData = _owners[tokenId];
        tokenData = _setDataValidity(tokenData, vId);
        // Lock if changing to a dead status (forever lock)
        if (vId >= REDEEMED) {
            tokenData = _lockToken(tokenId, tokenData);
        }
        _owners[tokenId] = tokenData;
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
            _owners[tokenId] = _setTokenParam(
                _owners[tokenId],
                MPOS_ROYALTY,
                royalty/10,
                M_MASK_ROYALTY
            );
        }
    }

    /**
     * @dev Unlocks the token. The Redeem cancel functions 
     * call this to unlock the token.
     */
    function _unlockToken(uint256 _tokenId)
    private {
        _owners[_tokenId] = _setTokenParam(
            _owners[_tokenId],
            MPOS_LOCKED,
            UNLOCKED,
            BOOL_MASK
        );
        emit TokenUnlocked(_tokenId, address(this));
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
      * @dev Returns the baseURI at given index.
      */
    function baseURIArray(uint256 index)
    external view
    returns (string memory) {
        return _baseURIArray[index];
    }

    /**
     * @dev Token burning. This option is not available for live 
     * tokens, or with those that have a status below REDEEMED.
     * The token owner can only burn dead tokens. We keep 
     * the token "around" to prevent a hole in the token 
     * enumeration and so that we can retain data of what has 
     * been physically redeemed.
     */
    function burn(uint256 tokenId)
    public
    isOwnerOrApproved(tokenId) {
        uint256 _tokenData = _owners[tokenId];
        // 1. Check token validity is a dead status
        uint256 validity = _currentVId(_tokenData);
        if (validity < REDEEMED) {
            revert C9TokenNotBurnable(tokenId, validity);
        }
        // 2. Votes burn
        uint256 votesToBurn = _viewPackedData(_tokenData, MPOS_VOTES, MSZ_VOTES);
        unchecked {_totalVotes -= votesToBurn;}
        // 3. Zero address burn
        _burn(tokenId);
        // 4. Add to list of burned tokens
        _burnedTokens.push(uint24(tokenId));
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
     * @dev Returns the list of burned tokens.
     */
    function getBurned()
    external view
    returns (uint24[] memory burnedTokens) {
        burnedTokens = _burnedTokens;
    }

    /**
     * @dev Returns list of contracts this contract is linked to.
     */
    function getContracts()
    external view
    returns(address meta, address redeemer, address upgrader, address vH) {
        meta = contractMeta;
        redeemer = contractRedeemer;
        upgrader = contractUpgrader;
        vH = contractVH;
    }

    /**
     * @dev Returns the latest minted Id of the edition number.
     */
    function getEditionMaxMintId(uint256 edition)
    external view
    returns (uint256) {
        return _mintId[edition];
    }

    /**
     * @dev Returns an unpacked view of the ownerData.
     */
    function getOwnersParams(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (uint[9] memory xParams) {
        uint256 data = _owners[tokenId];
        xParams[0] = _viewPackedData(data, MPOS_XFER_COUNTER, MSZ_XFER_COUNTER);
        xParams[1] = _viewPackedData(data, MPOS_VALIDITYSTAMP, USZ_TIMESTAMP);
        xParams[2] = _currentVId(data);
        xParams[3] = data>>MPOS_UPGRADED & BOOL_MASK;
        xParams[4] = data>>MPOS_DISPLAY & BOOL_MASK;
        xParams[5] = data>>MPOS_LOCKED & BOOL_MASK;
        xParams[6] = _viewPackedData(data, MPOS_INSURANCE, MSZ_INSURANCE);
        xParams[7] = _viewPackedData(data, MPOS_ROYALTY, MSZ_ROYALTY) * 10;
        xParams[8] = _viewPackedData(data, MPOS_VOTES, MSZ_VOTES);
    }

    /**
     * @dev Returns view of the barCodeData.
     */
    function getQRData(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (uint256) {
        return _cTokenData[tokenId];
    }

    /**
     * @dev Returns the list of redeemed tokens.
     */
    function getRedeemed()
    external view
    returns (uint24[] memory redeemedTokens) {
        redeemedTokens = _redeemedTokens;
    }

    /**
     * @dev Returns an unpacked view of the tokenData.
     */
    function getTokenParams(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (uint256[11] memory xParams) {
        uint256 data = _uTokenData[tokenId];
        xParams[0] = _viewPackedData(data, UPOS_MINTSTAMP, USZ_TIMESTAMP);
        xParams[1] = _viewPackedData(data, UPOS_EDITION, USZ_EDITION);
        xParams[2] = _viewPackedData(data, UPOS_EDITION_MINT_ID, USZ_EDITION_MINT_ID);
        xParams[3] = _viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG);
        xParams[4] = _viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH);
        xParams[5] = _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG);
        xParams[6] = _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH);
        xParams[7] = _viewPackedData(data, UPOS_MARKERTUSH, USZ_MARKERTUSH);
        xParams[8] = _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL);
        xParams[9] = _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER);
        xParams[10] = _viewPackedData(data, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE);
    }

    /**
     * @dev Returns the name stored in token params.
     * This is in a separate function since it is a string 
     * of unknown length that needs to be checked in a special 
     * way prior to returning.
     */
    function getTokenParamsName(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (string memory name) {
        uint256 data = _uTokenData[tokenId];
        bytes19 b19Name = bytes19(uint152(data >> UPOS_NAME));
        uint256 i;
        for (i; i<19;) {
            if (b19Name[i] == 0x00) {
                break;
            }
            unchecked {++i;}
        }
        bytes memory bName = new bytes(i);
        for (uint256 j; j<i;) {
            bName[j] = b19Name[j];
            unchecked {++j;}
        }
        return string(bName);
    }

    /**
     * @dev Returns view of the barCodeData.
     */
    function isLocked(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        uint256 data = _owners[tokenId];
        return data>>MPOS_LOCKED & BOOL_MASK == 1 ? true : false;
    }

    /**
     * @dev See {IERC-5560 IRedeemable}
     * The IERC is not official, but the function is a good
     * idea to implement anyway for quick lookup.
     */
    function isRedeemable(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        return _isRedeemable(tokenId, _owners[tokenId]);
    }

    /**
     * @dev
     * A view function to check if a token is already redeemed.
     */
    function isRedeemed(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        if (_currentVId(_owners[tokenId]) == REDEEMED) {
            return true;
        }
        return false;
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
            _totalVotes += votes;
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
    function preRedeemable(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (bool) {
        return _preRedeemable(_uTokenData[tokenId]);
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
        uint256 _tokenOffsetMax;
        unchecked {_tokenOffset + (_batchSize*UINT_SIZE);}
        uint256 _tokenId;
        for (_tokenOffset; _tokenOffset<_tokenOffsetMax;) {
            _tokenId = uint256(uint24(_redeemerData>>_tokenOffset));
            _unlockToken(_tokenId);
            unchecked {
                _tokenOffset += UINT_SIZE;
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
        uint256 _tokenOffsetMax;
        unchecked {_tokenOffset + (_batchSize*UINT_SIZE);}
        uint256 _tokenId;
        // Set all tokens to redeemed
        for (_tokenOffset; _tokenOffset<_tokenOffsetMax;) {
            _tokenId = uint256(uint24(redeemerData>>_tokenOffset));
            _setTokenValidity(_tokenId, REDEEMED);
            _redeemedTokens.push(uint24(_tokenId));
            unchecked {
                _tokenOffset += UINT_SIZE;
            }
        }
        // Update the token owner's redemption count
        _addRedemptionsTo(_ownerOf(_tokenId), _batchSize);
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
        IC9Redeemer(contractRedeemer).start(_msgSender(), tokenIds);
    }

    //>>>>>>> REDEEMER FUNCTIONS END

    /**
     * @dev Resets royalty information for the token id back to the 
     * global defaults.
     */
    function resetTokenRoyalty(uint256 tokenId)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
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
                _owners[tokenId],
                MPOS_ROYALTY,
                MSZ_ROYALTY
            ) * 10;
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
            U_MASK_ROYALTIES_DUE
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

    /*
     * @dev Sets the token validity.
     */
    function setTokenValidity(uint256 tokenId, uint256 vId)
    external
    onlyRole(VALIDITY_ROLE)
    isContract()
    requireMinted(tokenId)
    notDead(tokenId) {
        uint256 _tokenValidity = _currentVId(_owners[tokenId]);
        if (vId == _tokenValidity) {
            revert ValueAlreadySet();
        }
        if (vId >= REDEEMED) {
            if (_tokenValidity == VALID) {
                revert CannotValidToDead(tokenId, vId);
            }
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
     * @dev Returns if the contract is set to SVGonly mode.
     */
    function svgOnly()
    external view
    returns (bool) {
        return _svgOnly;
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
        return string(
            IC9MetaData(contractMeta).svgImage(
                tokenId,
                _owners[tokenId],
                _uTokenData[tokenId],
                _cTokenData[tokenId]
            )
        );
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
     
    function tokenURI(uint256 tokenId)
    public view
    override(ERC721)
    requireMinted(tokenId)
    returns (string memory) {
        return string(
            IC9MetaData(contractMeta).metaData(
                tokenId,
                _owners[tokenId],
                _uTokenData[tokenId],
                _cTokenData[tokenId]
            )
        );
    }

    /**
     * @dev Returns the number of burned tokens.
     */
    function totalBurned()
    external view
    returns (uint256) {
        return _burnedTokens.length;
    }

    /**
     * @dev Returns the number of redeemed tokens.
     */
    function totalRedeemed()
    external view
    returns (uint256) {
        return _redeemedTokens.length;
    }

    /**
     * @dev Returns the number of redeemed tokens.
     */
    function validityStatus(uint256 tokenId)
    external view
    requireMinted(tokenId)
    returns (uint256) {
        uint256 data = _owners[tokenId];
        return _currentVId(data);
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
}