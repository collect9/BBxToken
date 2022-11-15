// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./C9MetaData.sol";
import "./C9OwnerControl.sol";
import "./C9Redeemer.sol";
import "./C9Shared.sol";
import "./C9SVG.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./utils/EthPricer.sol";

interface IC9Token {
    function ownerOf(uint256 _tokenId) external view returns (address);
    function preRedeemable(uint256 _tokenId) external view returns(bool);
    function redeemFinish(uint256 _tokenId) external;
    function redeemStart(uint256 _tokenId) external;
    function tokenLocked(uint256 _tokenId) external view returns(bool);
    function tokenUpgraded(uint256 _tokenId) external view returns(bool);
}

contract C9Token is IC9Token, ERC721Enumerable, ERC2981, C9OwnerControl {
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    /**
     * @dev Flag that may enable IPFS artwork versions to be 
     * displayed in the future. Is it set to false by default
     * until upgrade capability is confirmed and ready. The 
     * SVG only flag acts as a fail safe to return to SVG 
     * only mode later on.
     */
    bool public svgOnly = true;
    string[2] private __baseURI;
    function _baseURI() internal view override returns(string memory) {
        return __baseURI[0];
    }

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI = "https://collect9.io/metadata/Collect9RWARBBToken.json";
    function contractURI()
        external view returns (string memory) {
            return _contractURI;
    }
     
    /**
     * @dev Potential token upgrade path params.
     * Upgraded involves setting token to point to baseURI and 
     * display a .png version. Upgraded tokens may have 
     * the tokenUpgradedView flag toggled to go back and 
     * forth between SVG and PNG views.
     */
    bool public tokensUpgradable;
    mapping(uint256 => bool) private _tokenUpgraded;
    function tokenUpgraded(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns (bool) {
            return _tokenUpgraded[_tokenId];
    }
    mapping(uint256 => bool) private _tokenImgView;
    uint16 public tokensUpgradePrice = 100; //usd
    event Upgraded(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 indexed price
    );

    /**
     * @dev Redemption definitions.
     */
    uint32 public preReleasePeriod = 31556926; //seconds
    mapping(uint256 => bool) private _tokenLocked;
    function tokenLocked(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns(bool) {
            return _tokenLocked[_tokenId];
    }
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
    mapping(uint256 => C9Shared.TokenInfo) private _tokens;

    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenInfo has already been minted. The bool return is 
     * responsible for determining whether or not to increment 
     * the editionID.
     */
    mapping(bytes32 => bool) private _attrComboExists;

    /**
     * @dev _mintId stores the minting ID number for up to 96 editions.
     * This means that 96 of some physical collectible, differentiated 
     * only by authentication certificate id can be minted. 96 is chosen 
     * for packed storage purposes as it takes up the same space as 7x 
     * uint256.
     */
    uint16[96] private _mintId;

    /**
     * @dev The meta and SVG contracts.
     */
    address public contractMeta;
    address public contractPriceFeed;
    address public contractRedeemer;
    address public contractSVG;

    /**
     * @dev The constructor sets the default royalty of the token 
     * to 5.0%. Owner needs to be set because default owner from 
     * ownable is not payable. All addresses can be updated after 
     * deployment.
     */
    constructor(
        address metaContract_,
        address priceFeedContract_,
        address redeemerContract_,
        address svgContract_
        )
        ERC721("Collect9 NFTs", "C9T") {
            contractMeta = metaContract_;
            contractPriceFeed = priceFeedContract_;
            contractRedeemer = redeemerContract_;
            contractSVG = svgContract_;
            _setDefaultRoyalty(owner, 500);
    }

    modifier addressNotSame(address _old, address _new) {
        if (_old == _new) revert("C9Token: set address same");
        _;
    }

    modifier inRedemption(uint256 _tokenId, bool status) {
        if (_tokens[_tokenId].validity == 4) revert("C9Token: token already redeemed");
        if (tokenLocked(_tokenId) != status) revert("C9Token: redemption status disallowed");
        _;
    }

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) revert("C9Token: unauthorized");
        if (_tokens[_tokenId].validity == 2) _tokens[_tokenId].validity = 0;
        _;
    }

    modifier limitRoyalty(uint256 _royalty) {
        if (_royalty > 999) revert("C9Token: royalty set too high");
        _;
    }

    modifier notRedeemed(uint256 _tokenId) {
        if (_tokens[_tokenId].validity == 4) revert("C9Token: token already redeemed");
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        if (!_exists(_tokenId)) revert("C9Token: non-existent token id");
        _;
    }

    /**
     * @dev Required overrides.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721Enumerable)
        inRedemption(tokenId, false) {
            super._beforeTokenTransfer(from, to, tokenId);
            if (_tokens[tokenId].validity == 2) _tokens[tokenId].validity = 0;
    }

    function supportsInterface(bytes4 interfaceId)
        public view
        override(AccessControl, ERC721Enumerable, ERC2981)
        returns (bool) {
            return super.supportsInterface(interfaceId);
    }

    /**
     * @dev The token burning required for the redemption process.
     * Require statement is the same as in ERC721Burnable.
     * Note the `attrComboExists` of the token is not removed, thus 
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
            delete _tokens[_tokenId];
            delete _tokenLocked[_tokenId];
            delete _tokenUpgraded[_tokenId];
            delete _tokenImgView[_tokenId];
            _resetTokenRoyalty(_tokenId);
    }

    /**
     * @dev Testing function only, remove for release.
     */
    function burnAll()
        public
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 totalSupply = totalSupply();
            for (uint256 i; i<totalSupply; i++) {
                burn(tokenByIndex(0));
            }
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
    function b64SVGImage(uint256 _tokenId)
        public view
        tokenExists(_tokenId)
        returns (string memory) {
            return Base64.encode(bytes(svgImage(_tokenId)));
    }

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function getPhysicalHash(C9Shared.TokenInfo calldata _input, uint256 _edition)
        internal pure
        returns (bytes32) {
            return keccak256(
                abi.encodePacked(
                    _edition,
                    _input.tag,
                    _input.tush,
                    _input.gentag,
                    _input.gentush,
                    _input.markertush,
                    _input.spec,
                    _input.name
                )
            );
    }

    /**
     * @dev Minting function. This checks and sets the `_edition` based on 
     * the `TokenInfo` input attributes, sets the `__mintId` based on 
     * the `_edition`, sets the royalty, and then stores all of the 
     * attributes required to construct the SVG in the tightly packed 
     * `TokenInfo` structure.
     *
     * Requirements:
     *
     * - `_input` tag and tush country id mappings are valid.
     * - `_input` royalty is <9.99%.
    */
    function mint1(C9Shared.TokenInfo calldata _input)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_input.royalty) {
            uint256 _uid = uint256(_input.id);
            if (_uid == 0) {
                revert ("C9TokenMint: cert id cannot be 0");
            }
            uint256 _edition = _input.edition;
            if (_edition == 0) {
                bytes32 _data;
                for (uint256 i; i<_mintId.length; i++) {
                    _data = getPhysicalHash(_input, i+1);
                    if (!_attrComboExists[_data]) {
                        _edition = i+1;
                        break;
                    }
                }
            }
            if (_edition > _mintId.length-1) {
                revert("C9TokenMint: edition overlow");
            }
            // Get the edition mint id
            uint256 __mintId = _input.mintid == 0 ? _mintId[_edition] + 1 : _input.mintid;
            if (__mintId == 0) {
                revert("C9TokenMint: mint id cannot be 0");
            }
            // Store token meta data
            _tokens[_uid] = C9Shared.TokenInfo(
                _input.validity,
                uint8(_edition),
                _input.tag,
                _input.tush,
                _input.gentag,
                _input.gentush,
                _input.markertush,
                _input.spec,
                _input.rtier,
                uint16(__mintId),
                _input.royalty,
                _input.id,
                uint48(block.timestamp),
                _input.name,
                _input.qrdata,
                _input.bardata
            );
            // Set royalty info
            (address _royaltyAddress,) = royaltyInfo(0, 10000); 
            _setTokenRoyalty(_uid, _royaltyAddress, _input.royalty);
            // Mint token
            _mint(msg.sender, _uid);
            // Store attribute combo
            _attrComboExists[getPhysicalHash(_input, _edition)] = true;
            if (_input.mintid == 0) {
                _mintId[_edition] = uint16(__mintId);
            }
    }

    /**
     * @dev Helps makes the overall minting process faster and cheaper 
     * on average per mint.
    */
    function mintN(C9Shared.TokenInfo[] calldata _input, uint256 N)
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
            return block.timestamp-_tokens[_tokenId].mintstamp < preReleasePeriod;
    }

    /**
     * @dev Required override for IC9Token that the redeemer uses.
     */
    function ownerOf(uint256 tokenId)
        public view override(ERC721, IC9Token)
        returns (address) {
            return super.ownerOf(tokenId);
    }

    /**
     * @dev Allows user to cancel redemption process and resume 
     * token movement exchange capabilities.
     */
    function redeemCancel(uint256 _tokenId)
        external
        tokenExists(_tokenId)
        isOwner(_tokenId)
        inRedemption(_tokenId, true) {
            IC9Redeemer(contractRedeemer).cancelRedemption(_tokenId);
            delete _tokenLocked[_tokenId];
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
            _tokens[_tokenId].validity = 4;
            _tokens[_tokenId].mintstamp = uint48(block.timestamp);
            emit RedemptionFinish(ownerOf(_tokenId), _tokenId);
    }

    /**
     * @dev Starts the redemption process. Only the token holder can start.
     * Once started, the token is locked from further exchange. The user 
     * can still cancel the process before finishing.
     */
    function redeemStart(uint256 _tokenId)
        external override
        tokenExists(_tokenId)
        isOwner(_tokenId)
        inRedemption(_tokenId, false) {
            if (_tokens[_tokenId].validity != 0) {
                revert("C9Token: token status not valid");
            }
            if (preRedeemable(_tokenId)) {
                revert("C9Token: token pre-redeemable period not yet finished");
            }
            _tokenLocked[_tokenId] = true;
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
            return IC9SVG(contractSVG).returnSVG(ownerOf(_tokenId), _tokens[_tokenId]);
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
            bytes memory image;
            bool _upgraded = tokenUpgraded(_tokenId);
            bool _ipfsView = _tokenImgView[_tokenId];

            if (svgOnly || !_ipfsView) {
                // Onchain SVG
                image = abi.encodePacked(
                    ',"image":"data:image/svg+xml;base64,',
                    b64SVGImage(_tokenId)
                );
            }
            else {
                // Token upgraded, get view URI
                uint256 _view = _tokens[_tokenId].validity == 4 ? 1 : 0;
                image = abi.encodePacked(
                    ',"image":"',
                    __baseURI[_view], Strings.toString(_tokenId), '.png'
                );
            }

            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            IC9MetaData(contractMeta).metaNameDesc(_tokens[_tokenId]),
                            image,
                            IC9MetaData(contractMeta).metaAttributes(_tokens[_tokenId], _upgraded)
                        )
                    )
                )
            );
    }

    /**
     * @dev Allows the token holder to upgrade their token.
     */
    function upgradeToken(uint256 _tokenId)
        external payable
        tokenExists(_tokenId)
        isOwner(_tokenId) {
            if (!tokensUpgradable) {
                revert("C9TokenUpgrade: tokens not upgradable");
            }
            if (tokenUpgraded(_tokenId)) {
                revert("C9TokenUpgrade: token already upgraded");
            }
            if (preRedeemable(_tokenId)) {
                revert("C9TokenUpgrade: token not upgradable during its pre-redeemable period");
            } 
            uint256 upgradeWeiPrice = IC9EthPriceFeed(contractPriceFeed).getTokenWeiPrice(tokensUpgradePrice);
            if (msg.value != upgradeWeiPrice) {
                revert("C9TokenUpgrade: incorrect payment amount");
            }
            (bool success,) = payable(owner).call{value: msg.value}("");
            if(!success) {
                revert("C9TokenUpgrade: payment failure");
            }
            _tokenUpgraded[_tokenId] = true;
            emit Upgraded(msg.sender, _tokenId, tokensUpgradePrice);
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
                revert("C9Token: uri already set");
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
                revert("C9Token: uri already set");
            }
            _contractURI = _newContractURI;
    }

    /**
     * @dev Allows the contract owner to update the global royalties 
     * receving address and amount.
     */
    function setDefaultRoyalties(address _address, uint256 _defaultRoyalty)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_defaultRoyalty) {
            (address _royaltyAddress, uint256 _salePrice) = royaltyInfo(0, 10000);
            if (_address == _royaltyAddress && _salePrice == _defaultRoyalty) {
                revert("C9Token: default royalty vals already set");
            }
            _setDefaultRoyalty(_address, uint96(_defaultRoyalty));
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
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setContractPriceFeed(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(contractPriceFeed, _address) {
            contractPriceFeed = _address;
    }

    /**
     * @dev Gets or sets the global token redeemable period.
     */
    function setPreReleasePeriod(uint32 _period)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (preReleasePeriod == _period) {
                revert("C9Token: period already set");
            }
            preReleasePeriod = _period;
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
     * @dev Set SVG flag to either display on-chain SVG (true) or IPFS 
     * version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     */
    function setSvgOnly(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (svgOnly == _flag) {
                revert("C9Token: bool already set");
            }
            svgOnly = _flag;
    }

    /**
     * @dev Allows the contract owner to update the royalties 
     * per token basis, within limits.
     * This may be useful if Collect9 eventually tokenizes 
     * on behalf of others.
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
        _tokens[_tokenId].royalty = uint16(_newRoyalty);
        (address _royaltyAddress,) = royaltyInfo(0, 100);
        _royaltyAddress != address(0) ?
            _setTokenRoyalty(_tokenId, _customRoyaltyAddress, uint96(_newRoyalty)) :
            _setTokenRoyalty(_tokenId, _royaltyAddress, uint96(_newRoyalty));
    }

    /**
     * @dev Updates the token validity status.
     * Validity will not prevent or pause transfers. It is 
     * only a display flag to let users know of the token's 
     * status.
     */
    function setTokenValidity(uint256 _tokenId, uint8 _vId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        tokenExists(_tokenId)
        notRedeemed(_tokenId) {
            if (_vId > 3)                           revert("C9Token: invalid vId");
            if (_tokens[_tokenId].validity == _vId) revert("C9Token: vId already set");
            _tokens[_tokenId].validity = _vId;
    }

    /**
     * @dev Allows holder to set back to SVG view after 
     * token has already been upgraded. Flag must be set 
     * back to true for upgraded view to show again.
     */
    function setTokenImgView(uint256 _tokenId, bool _flag)
        external
        tokenExists(_tokenId)
        isOwner(_tokenId) {
            if (!tokenUpgraded(_tokenId))          revert("C9Token: token is not upgraded");
            if (_tokenImgView[_tokenId] == _flag)  revert("C9Token: view already set");
            _tokenImgView[_tokenId] = _flag;
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setTokensUpgradePrice(uint16 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (tokensUpgradePrice == _price) {
                revert("C9Token: price already set");
            }
            tokensUpgradePrice = _price;
    }

    /**
     * @dev Set token upgrade capability flag.
     */
    function setTokensUpgradable(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (tokensUpgradable == _flag) {
                revert("C9Token: bool already set");
            }
            tokensUpgradable = _flag;
    }
}