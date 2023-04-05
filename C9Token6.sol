// SPDX-License-Identifier: MIT
pragma solidity >0.8.17;
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG2.sol";
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
    address internal contractMeta;
    address internal contractUpgrader;
    address internal contractVH;

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
    uint256 public preRedeemablePeriod; //seconds

    /**
     * @dev Mappings that hold all of the token info required to 
     * construct the 100% on chain SVG.
     * Many properties within _uTokenData that define 
     * the physical collectible are immutable by design.
     */
    mapping(uint256 => address) private _rTokenData;
    mapping(uint256 => uint256) private _cTokenData;
    mapping(uint256 => uint256) internal _uTokenData;

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
        preRedeemablePeriod = 31600000; // ~1 year
        _svgOnly = true;
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
        _transferEvent(_ownerOf(tokenId), address(0), tokenId);
        _owners[tokenId] &= ~(uint256(type(uint160).max)<<MPOS_OWNER); // Set zero address
        delete _tokenApprovals[tokenId];
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

        uint256 editionMintId;
        uint256 tokenId;
        address to = _msgSender();
        uint256 _to = uint256(uint160(to));

        for (uint256 i; i<batchSize;) {
            _input = input[i];

            // Checks
            tokenId = _input.tokenid;
            if (tokenId == 0) {
                revert ZeroTokenId();
            }
            if (_exists(tokenId)) {
                revert TokenAlreadyMinted(tokenId);
            }

            // Get the edition mint id
            if (_input.mintid != 0) {
                editionMintId = _input.mintid;
            }
            else {
                editionMintId = _mintId[_input.edition];
                unchecked {++editionMintId;}
                _mintId[_input.edition] = uint16(editionMintId);
            }

            // All checks have passed, add to all tokens list
            _allTokens.push(uint24(tokenId));

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
            packedToken |= _input.edition<<UPOS_EDITION;
            packedToken |= editionMintId<<UPOS_EDITION_MINT_ID;
            packedToken |= _input.cntrytag<<UPOS_CNTRYTAG;
            packedToken |= _input.cntrytush<<UPOS_CNTRYTUSH;
            packedToken |= _input.gentag<<UPOS_GENTAG;
            packedToken |= _input.gentush<<UPOS_GENTUSH;
            packedToken |= _input.markertush<<UPOS_MARKERTUSH;
            packedToken |= _input.special<<UPOS_SPECIAL;
            packedToken |= _input.raritytier<<UPOS_RARITYTIER;
            packedToken |= _input.royaltiesdue<<UPOS_ROYALTIES_DUE;
            packedToken |= uint256(uint152(bytes19(bytes(_input.name))))<<UPOS_NAME;
            _uTokenData[tokenId] = packedToken;

            // Store token data for SVG
            _cTokenData[tokenId] = _input.cData;

            // This is a waste but there's no transfer batch
            _transferEvent(address(0), to, tokenId);

            unchecked {
                ++i;
                votes += _input.votes;
            }
        }
        return votes;
    }

    function _lockToken(uint256 tokenId, uint256 tokenData)
    internal
    returns (uint256) {
        emit TokenLocked(tokenId, _msgSender());
        return tokenData |= BOOL_MASK<<MPOS_LOCKED;
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
    internal {
        _owners[_tokenId] &= ~(BOOL_MASK<<MPOS_LOCKED);
        emit TokenUnlocked(_tokenId, _msgSender());
    }

    /**
     * @dev Temp function only used in the contrat tests.
     */
    function adminLock(uint256 tokenId)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        _owners[tokenId] = _lockToken(tokenId, _owners[tokenId]);
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
        uint256 _ownerData = _owners[tokenId];
        // 1. Check token validity is a dead status
        uint256 validity = _currentVId(_ownerData);
        if (validity < REDEEMED) {
            revert C9TokenNotBurnable(tokenId, validity);
        }
        // 2. Votes burn
        uint256 votesToBurn = _viewPackedData(_ownerData, MPOS_VOTES, MSZ_VOTES);
        unchecked {_totalVotes -= votesToBurn;}
        // 3. Zero address burn (emits transfer event)
        _burn(tokenId);
        // 4. Add to list of burned tokens
        _burnedTokens.push(uint24(tokenId));
        // 5. Update burners balances (we don't add a transfer, just like minting doesn't add one)
        (uint256 burnerBalance, uint256 burnerVotes,,) = ownerDataOf(_msgSender());
        unchecked {
            --burnerBalance;
            burnerVotes -= votesToBurn;
        }
        uint256 balances = _balances[_msgSender()];
        balances &= ~(MASK_BURNER<<APOS_BALANCE);
        balances |= burnerBalance<<APOS_BALANCE;
        balances |= burnerVotes<<APOS_VOTES;
        _balances[_msgSender()] = balances;
    }

    /**
     * @dev When a single burn is too expensive but you
     * don't want to burn all.
     */
    function burnBatch(uint256[] calldata tokenIds)
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
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    function contractURI()
    external view
    returns (string memory) {
        return string.concat(
            "https://", _contractURI, ".json"
        );
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
    external view virtual
    returns(address meta, address pricer, address upgrader, address vH) {
        meta = contractMeta;
        pricer = address(0);
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
     * @dev Returns the latest minted Id of the edition number.
     */
    function getInsuredsValue(uint256[] memory tokenIds)
    public view
    returns (uint256 value) {
        uint256 _batchSize = tokenIds.length;
        uint256 _tokenId;
        for (uint256 i; i<_batchSize;) {
            _tokenId = tokenIds[i];
            if (!_exists(_tokenId)) {
                revert InvalidToken(_tokenId);
            }
            unchecked {
                value += _viewPackedData(_owners[_tokenId], MPOS_INSURANCE, MSZ_INSURANCE);
                ++i;
            }
        }
    }

    /**
     * @dev Returns an unpacked view of the ownerData.
     */
    function getOwnersParams(uint256 tokenId)
    external view
    returns (uint[9] memory xParams) {
        uint256 _ownerData = _owners[tokenId];
        xParams[0] = _viewPackedData(_ownerData, MPOS_XFER_COUNTER, MSZ_XFER_COUNTER);
        xParams[1] = _viewPackedData(_ownerData, MPOS_VALIDITYSTAMP, USZ_TIMESTAMP);
        xParams[2] = _currentVId(_ownerData);
        xParams[3] = _isUpgraded(_ownerData);
        xParams[4] = _ownerData>>MPOS_DISPLAY & BOOL_MASK;
        xParams[5] = _ownerData>>MPOS_LOCKED & BOOL_MASK;
        xParams[6] = _viewPackedData(_ownerData, MPOS_INSURANCE, MSZ_INSURANCE);
        xParams[7] = _viewPackedData(_ownerData, MPOS_ROYALTY, MSZ_ROYALTY) * 10;
        xParams[8] = _viewPackedData(_ownerData, MPOS_VOTES, MSZ_VOTES);
    }

    /**
     * @dev Returns an unpacked view of the tokenData.
     */
    function getTokenParams(uint256 tokenId)
    external view
    returns (uint256[11] memory xParams) {
        uint256 _tokenData = _uTokenData[tokenId];
        xParams[0] = _viewPackedData(_tokenData, UPOS_MINTSTAMP, USZ_TIMESTAMP);
        xParams[1] = _viewPackedData(_tokenData, UPOS_EDITION, USZ_EDITION);
        xParams[2] = _viewPackedData(_tokenData, UPOS_EDITION_MINT_ID, USZ_EDITION_MINT_ID);
        xParams[3] = _viewPackedData(_tokenData, UPOS_CNTRYTAG, USZ_CNTRYTAG);
        xParams[4] = _viewPackedData(_tokenData, UPOS_CNTRYTUSH, USZ_CNTRYTUSH);
        xParams[5] = _viewPackedData(_tokenData, UPOS_GENTAG, USZ_GENTAG);
        xParams[6] = _viewPackedData(_tokenData, UPOS_GENTUSH, USZ_GENTUSH);
        xParams[7] = _viewPackedData(_tokenData, UPOS_MARKERTUSH, USZ_MARKERTUSH);
        xParams[8] = _viewPackedData(_tokenData, UPOS_SPECIAL, USZ_SPECIAL);
        xParams[9] = _viewPackedData(_tokenData, UPOS_RARITYTIER, USZ_RARITYTIER);
        xParams[10] = _viewPackedData(_tokenData, UPOS_ROYALTIES_DUE, USZ_ROYALTIES_DUE);
    }

    /**
     * @dev Returns the name stored in token params.
     * This is in a separate function since it is a string 
     * of unknown length that needs to be checked in a special 
     * way prior to returning.
     */
    function getTokenParamsName(uint256 tokenId)
    external view
    returns (string memory) {
        uint256 _tokenData = _uTokenData[tokenId];
        bytes19 b19Name = bytes19(uint152(_tokenData >> UPOS_NAME));
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
        balances &= ~(MASK_BALANCER<<APOS_BALANCE);
        balances |= minterBalance<<APOS_BALANCE;
        balances |= minterVotes<<APOS_VOTES;
        _balances[_msgSender()] = balances;
    }

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
        if (preRedeemablePeriod == period) {
            revert ValueAlreadySet();
        }
        preRedeemablePeriod = period;
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
        uint256 _val = _isUpgraded(tokenData);
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
        _metaUpdate(tokenId);
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
     * @dev Sets the token as upgraded. A separate upgrader contract 
     * will call this.
     */
    function setTokenUpgraded(uint256 tokenId)
    external
    onlyRole(UPGRADER_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
        uint256 _ownerData = _owners[tokenId];
        if (_isUpgraded(_ownerData) == UPGRADED) {
            revert TokenAlreadyUpgraded(tokenId);
        }
        _owners[tokenId] |= BOOL_MASK<<MPOS_UPGRADED;
        _metaUpdate(tokenId);
    }

    /**
     * @dev Returns the base64 representation of the SVG string. 
     * This is desired when including the string in json data which 
     * does not allow special characters found in hmtl/xml code.
     */
    function svgImage(uint256 tokenId)
    external view
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
     * @dev The cost to set/update should be comparable 
     * to updating insured values.
     */
    function updatedInsuranceValues(uint256[2][] calldata data)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 _batchSize = data.length;
        uint256 _tokenId;
        for (uint256 i; i<_batchSize;) {
            _tokenId = data[i][0];
            if (!_exists(_tokenId)) {
                revert InvalidToken(_tokenId);
            }
            _owners[_tokenId] = _setTokenParam(
                _owners[_tokenId],
                MPOS_INSURANCE,
                data[i][1],
                M_MASK_INSURANCE
            );
            unchecked {++i;}
        }
    }

    /**
     * @dev Returns the number of redeemed tokens.
     */
    function validityStatus(uint256 tokenId)
    external view
    returns (uint256) {
        uint256 _ownerData = _owners[tokenId];
        return _currentVId(_ownerData);
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