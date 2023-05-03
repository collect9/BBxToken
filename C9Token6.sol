// SPDX-License-Identifier: MIT
pragma solidity >0.8.17;
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG2.sol";
import "./utils/Helpers.sol";


import "./utils/C9ERC721EnumBasic.sol";

contract C9Token is ERC721IdEnumBasic {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Contracts this token contract interacts with.
     */
    address internal contractMeta;

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
     * @dev Redemption definitions and events. 
     * defines how long a token must exist before it can be 
     * redeemed.
     */
    uint24[] private _burnedTokens;

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
        _svgOnly = true;
    }

    /**
     * @dev Checks to see if caller is the token owner. 
     * ownerOf enforces token existing.
     */ 
    modifier isOwnerOrApproved(uint256 tokenId) {
        _isApprovedOrOwner(_msgSender(), ownerOf(tokenId), tokenId);
        _;
    }

    /**
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
     *
     * @param tokenId The tokenId to burn.
     */
    function _burn(uint256 tokenId)
    internal
    override {
        _transferEvent(_ownerOf(tokenId), address(0), tokenId);
        _owners[tokenId] &= ~(uint256(type(uint160).max)<<MPOS_OWNER); // Set zero address
        delete _tokenApprovals[tokenId];
    }

    /**
     * @dev Minting function.
     * The `TokenData` input attributes, sets the `__mintId` based on 
     * the `_edition`, sets the royalty, and then stores all of the 
     * attributes required to construct the SVG in the tightly packed 
     * uint256 slots.
     *
     * @param input The external minting data TokenData.
     * @return votes The number of votes created by this minting batch.
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

            // Pre-mint checks
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
            
            // Additional meta data storage in _uTokenData
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
            _uTokenData[tokenId] = packedToken; // Additional storage done

            // Store token data for SVG QR and bar codes
            _cTokenData[tokenId] = _input.cData;

            // This is a waste to call on every mint but there's no transfer batch
            _transferEvent(address(0), to, tokenId);

            unchecked {
                ++i;
                votes += _input.votes;
            }
        }
        return votes;
    }

    /**
     * @dev Since royalty info is already stored in the uTokenData,
     * we don't need a new slots for per token royalties, and can 
     * use the already existing uTokenData instead.
     *
     * @param tokenId The tokenId to set the per-token royalty of.
     * @param receiver The royalty receiver of tokenId.
     * @param royalty The royalty amount of tokenId.
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
     * @dev Convenience view function.
     *
     * @param index The index of the URI (either 0 or 1).
     * @return The baseURI for index.
     */
    function baseURIArray(uint256 index)
    external view
    returns (string memory) {
        return _baseURIArray[index];
    }

    /**
     * @dev Token burning. This option is not available for VALID 
     * tokens, or with those that have a status below REDEEMED (<4).
     * The token owner can only zero address burn dead tokens. 
     * Zero address tokens still exist to prevent a hole in the token 
     * enumeration, and to preserve a historical record on-chain 
     * of redeemed tokens.
     *
     * @param tokenId The tokenId to burn.
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
            --burnerBalance; // Subtract one from balance
            burnerVotes -= votesToBurn; // Subtract votes of token from voting balance
        }
        // 6. Save back to storage
        uint256 balances = _balances[_msgSender()];
        balances &= ~(MASK_BURNER<<APOS_BALANCE);
        balances |= burnerBalance<<APOS_BALANCE;
        balances |= burnerVotes<<APOS_VOTES;
        _balances[_msgSender()] = balances;
    }

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     *
     * @return string The contract URI.
     */
    function contractURI()
    external view
    returns (string memory) {
        return string.concat(
            "https://", _contractURI, ".json"
        );
    }

    /**
     * @dev Convenience view function.
     *
     * @return burnedTokens The array of burned tokenIds.
     */
    function getBurned()
    external view
    returns (uint24[] memory burnedTokens) {
        burnedTokens = _burnedTokens;
    }

    /**
     * @dev Convenience view function.
     *
     * @return meta The meta contract this contract is linked to.
     */
    function getContracts()
    external view virtual
    returns(address meta, address pricer) {
        meta = contractMeta;
        pricer = address(0);
    }

    /**
     * @dev Convenience view function.
     *
     * @param edition The editionId.
     * @return uint256 The current max mintId of edition.
     */
    function getEditionMaxMintId(uint256 edition)
    external view
    returns (uint256) {
        return _mintId[edition];
    }

    /**
     * @dev This function is called during the redemption process.
     * It determines the redemption fees to be paid.
     *
     * @param tokenIds Array of tokenIds
     * @return value The current insured value of tokenIds
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
     * @dev Convenienve view function.
     *
     * @param tokenId The tokenId to lookup.
     * @return xParams Unpacked view of _owners.
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
     * @dev Convenienve view function.
     *
     * @param tokenId The tokenId to lookup.
     * @return xParams Unpacked view of _uTokenData.
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
     * @dev Parses name stored in the metadata. It is a string 
     * of unknown length that is parsed to ensure no null bytes 
     * are present in the return.
     *
     * @param tokenId The tokenId to lookup.
     * @return string The name stored in _uTokenData.
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

    /* @dev Batch minting function. Batch minting reduces minting costs 
     * by largely negating call overhead.
     *
     * @param input The TokenData format token input.
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
     * @dev Resets royalty information for the tokenId back to the 
     * global defaults.
     *
     * @param tokenId The tokenId to reset royalty info of.
     */
    function resetTokenRoyalty(uint256 tokenId)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    requireMinted(tokenId)
    notDead(tokenId) {
        _setTokenRoyalty(tokenId, _royaltyReceiver, _royalty);
    }

    /**
     * @dev Custom EIP-2981.
     * This first this checks to see if the 
     * token has a royalty receiver and fraction assigned to it.
     * If not then it defaults to the contract wide values.
     *
     * @param tokenId EIP-2981 definition.
     * @param salePrice EIP-2981 definition.
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
     * @dev Sets the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork (i.e, on ipfs), the 
     * contract will need to set the IPFS location.
     *
     * @param newBaseURI The new baseURI to set.
     * @param idx The index of the baseURI to set (either 0 or 1).
     */
    function setBaseUri(string calldata newBaseURI, uint256 idx)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (idx > 1) {
            revert IndexOOB();
        }
        if (Helpers.stringEqual(_baseURIArray[idx], newBaseURI)) {
            revert URIAlreadySet();
        }
        bytes calldata _bBaseURI = bytes(newBaseURI);
        uint256 len = _bBaseURI.length;
        if (bytes1(_bBaseURI[len-1]) != 0x2f) {
            revert URIMissingEndSlash();
        }
        _baseURIArray[idx] = newBaseURI;
    }

    /**
     * @dev Sets the meta data contract address.
     *
     * @param _address The new contract address.
     */
    function setContractMeta(address _address)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    addressNotSame(contractMeta, _address) {
        contractMeta = _address;
    }

    /**
     * @dev Sets the contractURI.
     *
     * @param newContractURI The new contractURI link.
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
     * @dev Set royalties due if token validity status 
     * is ROYALTIES.
     *
     * @param tokenId The tokenId to set royalties due for.
     * @param amount The royalties due in USD.
     */
    function setRoyaltiesDue(uint256 tokenId, uint256 amount)
    external
    onlyRole(VALIDITY_ROLE)
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
     * @dev Allows NFT owner to toggle the SVG/external display flag.
     * Flag must be set to true for external 
     * view to show.
     *
     * @param tokenId The tokenId.
     * @param flag The SVG/external display flag to set.
     * @notice Token must be upgraded otherwise this will revert.
     *
     * Emits metaDataUpdate event.
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
        _metaUpdateEvent(tokenId);
    }

    /**
     * @dev Allows the contract owner to set royalties 
     * on a per token basis.
     *
     * @param tokenId The tokenId to set royalties of.
     * @param royalty The new royalty value in bps.
     * @param receiver The royalty receiver for this tokenId.
     * @notice Set receiver to the null address to use the already 
     * default global set royalty address.
     * @notice Updating the receiver the first time is nearly as
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
     * @dev Sets the token as upgraded.
     *
     * @param tokenId The tokenId to upgrade.
     *
     * Emits metaDataUpdate event.
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
        _metaUpdateEvent(tokenId);
    }

    /**
     * @dev Returns the on-chain SVG image display of tokenId.
     *
     * @param tokenId The tokenId to lookup.
     * @return string The SVG image.
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
     * @dev Convenience view function.
     *
     * @return bool If the contract is set to display SVG only 
     * regardless of token upgrades.
     */
    function svgOnly()
    external view
    returns (bool) {
        return _svgOnly;
    }

    /**
     * @dev Sets the SVG flag to either display on-chain SVG (true) or  
     * external version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     *
     * @param toggle The toggle to set _svgOnly to.
     *
     * Emits BatchMetadataUpdate event for all tokens.
     */
    function toggleSvgOnly(bool toggle)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_svgOnly == toggle) {
            revert BoolAlreadySet();
        }
        _svgOnly = toggle;
        metaUpdateAllEvent();
    }

    /**
     * @dev Required override that returns fully onchain constructed 
     * json output that includes the SVG image. If a baseURI is set and 
     * the token has been upgraded and the svgOnly flag is false, the 
     * baseURI to the external image will be called instead.
     *
     * @param tokenId The tokenId to lookup.
     * @return string The JSON output (NFT standard).
     * @notice It seems like if the baseURI method fails after upgrade,
     * OpenSea still displays the cached on-chain version.
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
     * @dev Convenience view function.
     *
     * @return The number of burned tokens.
     */
    function totalBurned()
    external view
    returns (uint256) {
        return _burnedTokens.length;
    }

    /**
     * @dev Updates the insured values of the tokens.
     *
     * @param data The data array as [tokenId, insuredValue].
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
     * @dev Disables self-destruct functionality.
     *
     * @param receiver The address to receive any remaining balance.
     * @param confirm Confirmation of destruction of the contract.
     * @notice Even if admin gets through the confirm is 
     * hardcoded to false.
     */
    function __destroy(address receiver, bool confirm)
    public override
    onlyRole(DEFAULT_ADMIN_ROLE) {
        confirm = false;
        super.__destroy(receiver, confirm);
    }
}