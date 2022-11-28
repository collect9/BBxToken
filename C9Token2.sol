// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./utils/ERC721Enum32.sol";

//import "./C9MetaData.sol";
import "./C9OwnerControl.sol";
import "./C9Redeemer.sol";
import "./C9Struct.sol";
//import "./C9SVG.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";

interface IC9Token {
    function preRedeemable(uint256 _tokenId) external view returns(bool);
    function redeemFinish(uint256 _tokenId) external;
    function redeemStart(uint256 _tokenId) external;
    function setTokenUpgraded(uint256 _tokenId) external;
    function tokenLocked(uint256 _tokenId) external view returns(bool);
    function tokenUpgraded(uint256 _tokenId) external view returns(bool);
}

contract C9Token is IC9Token, C9Struct, ERC721Enumerable, C9OwnerControl {
    /**
     * @dev Contract access roles.
     */
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VALIDITY_ROLE = keccak256("VALIDITY_ROLE");

    /**
     * @dev Default royalty.
     */
    uint256 public royaltyDefault;
    address public royaltyReceiver;

    /**
     * @dev The meta and SVG contracts.
     */
    address public contractMeta;
    address public contractRedeemer;
    address public contractSVG;

    /**
     * @dev Flag that may enable IPFS artwork versions to be 
     * displayed in the future. Is it set to false by default
     * until upgrade capability is confirmed and ready. The 
     * SVG only flag acts as a fail safe to return to SVG 
     * only mode later on.
     */
    bool public svgOnly = true;
    string[2] private __baseURI;

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI = "collect9.io/metadata/C9T";

    /**
     * @dev Redemption definitions.
     */
    uint256 public preReleasePeriod = 31556926; //seconds
    event RedemptionCancel(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedemptionFinish(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );
    event RedemptionStart(
        address indexed tokenOwner,
        uint256 indexed tokenId
    );

    /**
     * @dev Structure that holds all of the token info required to 
     * construct the 100% on chain SVG.
     */
    mapping(uint256 => address) private _rTokenData;
    mapping(uint256 => uint256) private _uTokenData;
    mapping(uint256 => string[3]) private _sTokenData;

    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenInfo has already been minted. The bool return is 
     * responsible for determining whether or not to increment 
     * the editionID.
     */
    mapping(bytes32 => bool) private _tokenComboExists;

    /**
     * @dev _mintId stores the minting ID number for up to 96 editions.
     * This means that 96 of some physical collectible, differentiated 
     * only by authentication certificate id can be minted. 96 is chosen 
     * for packed storage purposes as it takes up the same space as 7x 
     * uint256.
     */
    uint16[96] private _mintId;

    /**
     * @dev The constructor sets the default royalty of the token 
     * to 5.0%. Owner needs to be set because default owner from 
     * ownable is not payable. All addresses can be updated after 
     * deployment.
     */
    constructor(
        // address metaContract_,
        // address priceFeedContract_,
        // address redeemerContract_,
        // address svgContract_
        )
        ERC721("Collect9 NFTs", "C9T") {
            // contractMeta = metaContract_;
            // contractPriceFeed = priceFeedContract_;
            // contractRedeemer = redeemerContract_;
            // contractSVG = svgContract_;
            royaltyDefault = 500;
            royaltyReceiver = owner;
    }

    modifier addressNotSame(address _old, address _new) {
        if (_old == _new) {
            _errMsg("address same");
        }
        _;
    }

    modifier inRedemption(uint256 _tokenId, bool status) {
        if (_getTokenParam(_tokenId, TokenProps.VALIDITY) == REDEEMED) {
            _errMsg("token is redeemed");
        }
        bool _locked = _getTokenParam(_tokenId, TokenProps.LOCKED) == 1 ? true : false;
        if (_locked != status) {
            _errMsg("redemption status disallows");
        }
        _;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) {
            _errMsg("unauthorized");
        }
        _checkActivity(_tokenId);
        _;
    }

    modifier limitRoyalty(uint256 _royalty) {
        if (_royalty > 999) {
            _errMsg("royalty too high");
        }
        _;
    }

    modifier notRedeemed(uint256 _tokenId) {
        if (_getTokenParam(_tokenId, TokenProps.VALIDITY) == REDEEMED) {
            _errMsg("token is redeemed");
        }
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        if (!_exists(_tokenId)) {
            _errMsg("non-existent token id");
        }
        _;
    }

    /**
     * @dev Required overrides.
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
        inRedemption(tokenId, false) {
            super._beforeTokenTransfer(from, to, tokenId, batchSize);
            _checkActivity(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view
        override(ERC721Enumerable, AccessControl)
        returns (bool) {
            return super.supportsInterface(interfaceId);
    }

    /**
     * @dev uTokenData is packed into a single uint256. This function
     * returns an unpacked array.
     */
    function getTokenParams(uint256 _tokenId)
        public view override
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
     * @dev Get a single entry from uTokenData based on an enum index.
     */
    function _getTokenParam(uint256 _tokenId, TokenProps _idx)
        internal view override
        returns(uint256) {
            return getTokenParams(_tokenId)[uint256(_idx)];
    }

    //>>>>>>> CUSTOM ERC2981 START

    /*
     * @dev Since royalty info is already stored in the uTokenData and the 
     * default receiver is owner, we don't need to write it out 
     * every time. Royalty limit is also enforced on the external 
     * function.
     */
    function _setTokenRoyalty(uint256 _tokenId, address _receiver, uint256 _royalty)
        internal {
            if (_receiver != royaltyReceiver && _receiver != address(0)) {
                _rTokenData[_tokenId] = _receiver;
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_ROYALTY,
                _royalty,
                65535
            );
    }

    /**
     * @dev Resets royalty information for the token id back to the global default.
     */
    function resetTokenRoyalty(uint256 _tokenId)
        onlyRole(DEFAULT_ADMIN_ROLE)
        external {
            if (_rTokenData[_tokenId] != address(0)) {
                delete _rTokenData[_tokenId]; // back to owner
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_ROYALTY,
                royaltyDefault,
                65535
            );
    }

    /**
     * @dev Receiver is royaltyReceiver(default is owner) unless otherwise specified
     * for that tokenId.
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        public view
        returns (address, uint256) {
            address receiver = _rTokenData[_tokenId];
            if (receiver == address(0)) {
                receiver = royaltyReceiver;
            }
            uint256 _fraction = _getTokenParam(_tokenId, TokenProps.ROYALTY);
            uint256 royaltyAmount = (_salePrice * _fraction) / 10000;
            return (receiver, royaltyAmount);
    }

    //>>>>>>> CUSTOM ERC2981 END

    /**
     * @dev This function is meant to automatically fix an inactive 
     * validity status when the owner interacts with the contract.
     * It is placed _beforeTokenTransfer and in the isOwner modifier.
     */
    function _checkActivity(uint256 _tokenId)
        internal {
            if (_getTokenParam(_tokenId, TokenProps.VALIDITY) == INACTIVE) {
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
            for (uint256 i; i<totalSupply; i++) {
                burn(tokenByIndex(0));
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
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function getPhysicalHash(TokenData calldata _input, uint256 _edition)
        internal pure
        returns (bytes32) {
            return keccak256(
                abi.encodePacked(
                    _edition,
                    _input.cntrytag,
                    _input.cntrytush,
                    _input.gentag,
                    _input.gentush,
                    _input.markertush,
                    _input.special,
                    _input.name
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
    function mint1(TokenData calldata _input)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_input.royalty) {
            // Get physical edition id
            uint256 _edition = _input.edition;
            if (_edition == 0) {
                bytes32 _data;
                for (uint256 i; i<_mintId.length; i++) {
                    _data = getPhysicalHash(_input, i+1);
                    if (!_tokenComboExists[_data]) {
                        _edition = i+1;
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
            if (_edition >= _mintId.length) {
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
            _sTokenData[_tokenId] = [
                _input.name,
                _input.qrdata,
                _input.brdata
            ];

            // Store token attribute combo
            _tokenComboExists[getPhysicalHash(_input, _edition)] = true;

            // Mint token
            _mint(msg.sender, _tokenId);
    }

    /**
     * @dev Helps makes the overall minting process faster and cheaper 
     * on average per mint.
    */
    function mintN(TokenData[] calldata _input, uint256 N)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            for (uint256 i; i<N; i++) {
                mint1(_input[i]);
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
            return block.timestamp-_getTokenParam(_tokenId, TokenProps.MINTSTAMP) < preReleasePeriod;
    }

    /**
     * @dev Allows user to cancel redemption process and resume 
     * token movement exchange capabilities.
     */
    function redeemCancel(uint256 _tokenId)
        external
        isOwner(_tokenId)
        inRedemption(_tokenId, true) {
            IC9Redeemer(contractRedeemer).cancelRedemption(_tokenId);
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_LOCKED,
                0,
                255
            );
            emit RedemptionCancel(msg.sender, _tokenId);
    }

    /**
     * @dev Redeemer function that can only be accessed by the external 
     * contract calling it. That contract calling it will be assigned 
     * to the redeemer role. Once the token validity is set to 4, it is 
     * not possible to change it back.
     */
    function redeemFinish(uint256 _tokenId)
        external override
        onlyRole(REDEEMER_ROLE)
        tokenExists(_tokenId)
        inRedemption(_tokenId, true) {
            _setTokenValidity(_tokenId, 4);
            emit RedemptionFinish(ownerOf(_tokenId), _tokenId);
    }

    /**
     * @dev Starts the redemption process. Only the token holder can start.
     * Once started, the token is locked from further exchange. The user 
     * can still cancel the process before finishing.
     */
    function redeemStart(uint256 _tokenId)
        external override
        isOwner(_tokenId)
        inRedemption(_tokenId, false) {
            if (_getTokenParam(_tokenId, TokenProps.VALIDITY) != VALID) {
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
            IC9Redeemer(contractRedeemer).startRedemption(_tokenId);
            emit RedemptionStart(msg.sender, _tokenId);
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
            return "";//IC9SVG(contractSVG).returnSVG(ownerOf(_tokenId), _tokens[_tokenId]);
    }

    /**
     * @dev View functions for other contracts.
     */
    function tokenLocked(uint256 _tokenId)
        external view override
        tokenExists(_tokenId)
        returns(bool) {
            uint256 _val = _getTokenParam(_tokenId, TokenProps.LOCKED);
            return Helpers.uintToBool(_val);
    }

    function tokenUpgraded(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns (bool) {
            uint256 _val = _getTokenParam(_tokenId, TokenProps.UPGRADED);
            return Helpers.uintToBool(_val);
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
            uint256 _val = _getTokenParam(_tokenId, TokenProps.DISPLAY);
            bool _ipfsView = Helpers.uintToBool(_val);
            bytes memory image;
            if (svgOnly || !_ipfsView) {// Onchain SVG
                image = abi.encodePacked(
                    ',"image":"data:image/svg+xml;base64,',
                    b64SVGImage(_tokenId)
                );
            }
            else {// Token upgraded, get view URI based on if redeemed or active
                uint256 _view = _getTokenParam(_tokenId, TokenProps.VALIDITY) == REDEEMED ? 1 : 0;
                image = abi.encodePacked(
                    ',"image":"',
                    __baseURI[_view],
                    _tokenId,
                    '.png'
                );
            }
            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            //IC9MetaData(contractMeta).metaNameDesc(_tokens[_tokenId]),
                            image
                            //IC9MetaData(contractMeta).metaAttributes(_tokens[_tokenId], _upgraded)
                        )
                    )
                )
            );
    }

    /**
     * @dev Updates the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork on IPFS, the 
     * contract will need to set the IPFS location.
     */
    function setBaseUri(string calldata _newBaseURI, uint256 _idx)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Helpers.stringEqual(__baseURI[_idx], _newBaseURI)) {
                _errMsg("uri already set");
            }
            __baseURI[_idx] = _newBaseURI;
    }

     /**
     * @dev Updates the contractURI.
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
     * @dev Allows the contract owner to update the global royalties 
     * receving address and amount.
     */
    function setDefaultRoyalties(address _royaltyReceiver, uint256 _royaltyDefault)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_royaltyDefault) {
            (address _royaltyAddress, uint256 _salePrice) = royaltyInfo(0, 10000);
            if (_royaltyReceiver == _royaltyAddress && _salePrice == _royaltyDefault) {
                _errMsg("default royalty vals already set");
            }
            if (_royaltyDefault != royaltyDefault) {
                royaltyDefault = _royaltyDefault;
            }
            if (_royaltyReceiver != address(0)) {
                royaltyReceiver = _royaltyReceiver;
            }
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setContractMeta(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractMeta, _address) {
            contractMeta = _address;
    }

    /**
     * @dev Updates the redemption data contract address.
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
     */
    function setPreReleasePeriod(uint256 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (preReleasePeriod == _period) {
                _errMsg("period already set");
            }
            if (_period > 63113852) { // 2 years max
                _errMsg("period too long");
            }
            preReleasePeriod = _period;
    }

    /**
     * @dev Updates the SVG display contract address.
     * This function will allow future SVG image display 
     * upgrades.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setRoyaltiesDue(uint256 _tokenId, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId) {
            if (_amount == 0) {
                _errMsg("amount must be > 0");
            }
            if (_getTokenParam(_tokenId, TokenProps.ROYALTIESDUE) == _amount) {
                _errMsg("due amt already set");
            }
            if (_getTokenParam(_tokenId, TokenProps.VALIDITY) != ROYALTIES) {
                _errMsg("token status not royalties due");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_ROYALTIESDUE,
                _amount,
                65535
            );
    }

    /**
     * @dev Allows contract to have a separate royalties receiver 
     * address. The default receiver is owner.
     */
    function setRoyaltyReceiver(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(royaltyReceiver, _address) {
            royaltyReceiver = _address;
    }

    /**
     * @dev Set SVG flag to either display on-chain SVG (true) or IPFS 
     * version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
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
     */
    function setTokenRoyalty(
        uint256 _tokenId,
        uint256 _newRoyalty,
        address _customRoyaltyAddress
    )
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    limitRoyalty(_newRoyalty)
    tokenExists(_tokenId)
    notRedeemed(_tokenId) {
        _uTokenData[_tokenId] = _setTokenParam(
            _uTokenData[_tokenId],
            POS_ROYALTY,
            _newRoyalty,
            65535
        );
        (address _royaltyAddress,) = royaltyInfo(0, 10000);
        if (_customRoyaltyAddress != address(0)) {
            _setTokenRoyalty(_tokenId, _customRoyaltyAddress, _newRoyalty);
        }
        else {
            _setTokenRoyalty(_tokenId, _royaltyAddress, _newRoyalty);
        }
    }

    /**
     * @dev Updates the token validity status.
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
            if (_getTokenParam(_tokenId, TokenProps.VALIDITY) == _vId) {
                _errMsg("vId already set");
            }
            uint256 _tokenData = _uTokenData[_tokenId];
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

    function setTokenValidity(uint256 _tokenId, uint256 _vId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
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
     */
    function setTokenDisplay(uint256 _tokenId, bool _flag)
        external
        isOwner(_tokenId) {
            if (!tokenUpgraded(_tokenId)) {
                _errMsg("token is not upgraded");
            }
            uint256 _val = _getTokenParam(_tokenId, TokenProps.DISPLAY);
            if (Helpers.uintToBool(_val) == _flag) {
                _errMsg("view already set");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_DISPLAY,
                _flag ? 1 : 0,
                255
            );
    }

    /**
     * @dev Potential token upgrade path params.
     * Upgraded involves setting token to point to baseURI and 
     * display a .png version. Upgraded tokens may have 
     * the tokenUpgradedView flag toggled to go back and 
     * forth between SVG and PNG views.
     */
    function setTokenUpgraded(uint256 _tokenId)
        external override
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId) {
            if (tokenUpgraded(_tokenId)) {
                _errMsg("token is already upgraded");
            }
            _uTokenData[_tokenId] = _setTokenParam(
                _uTokenData[_tokenId],
                POS_UPGRADED,
                1,
                255
            );
    }
}