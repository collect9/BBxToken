// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

import "./C9MetaData.sol";
import "./C9OwnerControl.sol";
import "./C9Redeemer.sol";
import "./C9Shared.sol";
import "./C9SVG.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./utils/EthPricer.sol";


interface IC9Token {
    function tokenRedemptionLock(uint256 _tokenId) external view returns(bool);
    function redeemFinish(uint256 _tokenId) external;
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
    bool public tokensUpgradable;
    bool public svgOnly = true;
    string private __baseURI = "";
    function _baseURI() internal view override returns(string memory) {
        return __baseURI;
    }

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string private _contractURI = "https://collect9.io/metadata/Collect9RWARBBToken.json";
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }
     
    /**
     * @dev Potential token upgrade path params.
     * Upgraded involves setting token to point to baseURI and 
     * display a .png version. Upgraded tokens may have 
     * the tokenUpgradedView flag toggled to go back and 
     * forth between SVG and PNG views.
     */
    mapping(uint256 => bool) _tokenUpgraded;
    mapping(uint256 => bool) _tokenUpgradedView;
    uint16 public upgradePrice = 100;
    event Upgraded(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 indexed price
    );
    mapping(uint256 => bool) private _tokenRedemptionLock;
    function tokenRedemptionLock(uint256 _tokenId)
        external view override
        tokenExists(_tokenId)
        returns(bool) {
            return _tokenRedemptionLock[_tokenId];
    }
    event RedemptionEvent(
        address indexed tokenOwner,
        uint256 indexed tokenId,
        string indexed status
    );

    /**
     * @dev Fail-safe pause in case something is wrong with the 
     * contract. Pausing will allow for a seemless upgrade or 
     * migration to an updated contract.
     */
    

    /**
     * @dev Structure that holds all of the token info required to 
     * construct the 100% on chain SVG.
     */
    mapping(uint256 => C9Shared.TokenInfo) _tokens;

    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenInfo has already been minted. The bool return is 
     * responsible for determining whether or not to increment 
     * the editionID.
     */
    mapping(bytes32 => bool) _attrComboExists;

    /**
     * @dev _mintId stores the minting ID number for up to 96 editions.
     * This means that 96 of some physical collectible, differentiated 
     * only by authentication certificate id can be minted. 96 is chosen 
     * for packed storage purposes as it takes up the same space as 7x 
     * uint256.
     */
    uint16[96] _mintId;

    /**
     * @dev The meta and SVG contracts.
     */
    address public metaContract;
    address public priceFeedContract;
    address public redemptionContract;
    address public svgContract;

    /**
     * @dev The address to send royalties to. This is defined so that it 
     * may be changed or updated later on to a non-owner address if
     * desired.
     */
    address public royaltyAddress;

    /**
     * @dev The constructor sets the default royalty of the token 
     * to 5.0%. Owner needs to be set because default owner from 
     * ownable is not payable. All addresses can be updated after 
     * deployment.
     */
    constructor(
        address _metaContract,
        address _svgContract,
        address _priceFeedContract
        )
        ERC721("Collect9 BBR NFTs", "C9B") {
            metaContract = _metaContract;
            priceFeedContract = _priceFeedContract;
            svgContract = _svgContract;
            royaltyAddress = owner;
            _setDefaultRoyalty(royaltyAddress, 500);
    }

    modifier limitRoyalty(uint16 _royalty) {
        require(_royalty < 1000, "Royalty set too high");
        _;
    }

    modifier tokenExists(uint256 _tokenId) {
        require(_exists(_tokenId), "Qry non-existent token");
        _;
    }

    modifier senderApproved(uint256 _tokenId) {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved");
        _;
    }

    /**
     * @dev Required overrides.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721Enumerable) {
            super._beforeTokenTransfer(from, to, tokenId);
            require(!_tokenRedemptionLock[tokenId], "Token is locked: currently being redeemed");
            require(_tokens[tokenId].validity != 5, "Token is locked: has already been redeemed");
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721Enumerable, ERC2981, AccessControl)
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
        senderApproved(_tokenId) {
            _burn(_tokenId);
            delete _tokens[_tokenId];
            delete _tokenUpgraded[_tokenId];
            delete _tokenUpgradedView[_tokenId];
            delete _tokenRedemptionLock[_tokenId];
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
    function getPhysicalHash(C9Shared.TokenInfo calldata _input, uint8 _edition)
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
            // Get the token edition number
            uint8 _edition = _input.edition;
            if (_edition == 0) {
                bytes32 _data;
                for (uint8 i=1; i<97; i++) {
                    _data = getPhysicalHash(_input, i);
                    if (!_attrComboExists[_data]) {
                        _edition = i;
                        break;
                    }
                }
            }
            // Get the edition mint id
            uint16 __mintId = _input.mintid == 0 ? _mintId[_edition] + 1 : _input.mintid;
            // Store token meta data
            _tokens[_uid] = C9Shared.TokenInfo(
                _input.validity,
                _edition,
                _input.tag,
                _input.tush,
                _input.gentag,
                _input.gentush,
                _input.markertush,
                _input.spec,
                _input.rtier,
                __mintId,
                _input.royalty,
                _input.id,
                uint56(block.timestamp),
                _input.name,
                _input.qrdata,
                _input.bardata
            );
            // Set royalty info
            _setTokenRoyalty(_uid, royaltyAddress, _input.royalty);
            // Mint token
            _mint(msg.sender, _uid);
            // Store attribute combo
            _attrComboExists[getPhysicalHash(_input, _edition)] = true;
            if (_input.mintid == 0) {
                _mintId[_edition] = __mintId;
            }
    }

    /**
     * @dev Helps makes the overall minting process faster and cheaper 
     * on average per mint.
    */
    function mintN(C9Shared.TokenInfo[] calldata _input, uint8 N)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            for (uint8 i; i<N; i++) {
                mint1(_input[i]);
            }
    }

    /**
     * @dev Allows user to cancel redemption process and resume 
     * token movement exchange capabilities.
     */
    function redeemCancel(uint256 _tokenId)
        external
        tokenExists(_tokenId)
        senderApproved(_tokenId) {
            IC9Redeemer(redemptionContract).cancelRedemption(_tokenId);
            delete _tokenRedemptionLock[_tokenId];
            emit RedemptionEvent(msg.sender, _tokenId, "TOKEN UNLOCK");
    }

    /**
     * @dev Redeemer function that can only be accessed by the external 
     * contract calling it. That contract calling it will be assigned 
     * to the redeemer role. Once the token validity is set to 5, it is 
     * not possible to change it back.
     */
    function redeemFinish(uint256 _tokenId)
        external override
        onlyRole(REDEEMER_ROLE)
        tokenExists(_tokenId) {
            require(_tokenRedemptionLock[_tokenId], "Token has not begun redemption process");
            _tokens[_tokenId].validity = 5;
            _tokens[_tokenId].mintstamp = uint56(block.timestamp);
            emit RedemptionEvent(ownerOf(_tokenId), _tokenId, "FINISHED");
    }

    /**
     * @dev Starts the redemption process. Only the token holder can start.
     * Once started, the token is locked from further exchange. The user 
     * can still cancel the process before finishing.
     */
    function redeemStart(uint256 _tokenId)
        external
        tokenExists(_tokenId)
        senderApproved(_tokenId) {
            require(_tokens[_tokenId].validity == 0, "Token must be marked VALID for redemption");
            _tokenRedemptionLock[_tokenId] = true;
            IC9Redeemer(redemptionContract).genRedemptionCode(_tokenId);
            emit RedemptionEvent(msg.sender, _tokenId, "TOKEN LOCK");
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
            return IC9SVG(svgContract).returnSVG(ownerOf(_tokenId), _tokens[_tokenId]);
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
            bool _upgraded = _tokenUpgraded[_tokenId];
            bytes memory image;
            if (!svgOnly && _upgraded && _tokenUpgradedView[_tokenId]) {
                image = abi.encodePacked(
                    ',"image":"',
                    _baseURI(), Strings.toString(_tokenId), '.png'
                );
            }
            else {
                image = abi.encodePacked(
                    ',"image":"data:image/svg+xml;base64,',
                    b64SVGImage(_tokenId)
                );
            }

            return string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            IC9MetaData(metaContract).metaNameDesc(_tokens[_tokenId]),
                            image,
                            IC9MetaData(metaContract).metaAttributes(_tokens[_tokenId], _upgraded)
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
        tokenExists(_tokenId) {
            require(_isApprovedOrOwner(msg.sender, _tokenId), "UPGRADER unauthorized");
            require(tokensUpgradable, "Upgrades are currently not enabled");
            require(Helpers.stringEqual(_baseURI(), ""), "baseURI not set");
            require(!_tokenUpgraded[_tokenId], "Token already upgraded");
            uint256 upgradeEthPrice = IC9EthPriceFeed(priceFeedContract).getTokenETHPrice(upgradePrice);
            require(msg.value == upgradeEthPrice, "Wrong amount of ETH");
            (bool success,) = payable(owner).call{value: msg.value}("");
            require(success, "Failed to send ETH");
            _tokenUpgraded[_tokenId] = true;
            _tokenUpgradedView[_tokenId] = true;
            emit Upgraded(msg.sender, _tokenId, upgradePrice);
    }

    /**
     * @dev Updates the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork on IPFS, the 
     * contract will need to set the IPFS location.
     */
    function setBaseUri(string calldata _newBaseURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            __baseURI = _newBaseURI;
    }

     /**
     * @dev Updates the contractURI.
     */
    function setContractUri(string calldata _newContractURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            _contractURI = _newContractURI;
    }

    /**
     * @dev Allows the contract owner to update the global royalties 
     * receving address and amount.
     */
    function setDefaultRoyalties(address _address, uint16 _defaultRoyalty)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        limitRoyalty(_defaultRoyalty) {
            royaltyAddress = _address;
            _setDefaultRoyalty(royaltyAddress, _defaultRoyalty);
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setMetaContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            metaContract = _address;
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setPriceFeedContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            priceFeedContract = _address;
    }

    /**
     * @dev Updates the SVG display contract address.
     * This function will allow future SVG image display 
     * upgrades.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setSVGContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            svgContract = _address;
    }

    /**
     * @dev Set SVG flag to either display on-chain SVG (true) or IPFS 
     * version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     */
    function setSvgOnly(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
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
        uint16 _newRoyalty,
        address _royaltyAddress
    )
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    limitRoyalty(_newRoyalty)
    tokenExists(_tokenId) {
        _tokens[_tokenId].royalty = _newRoyalty;
        _royaltyAddress != address(0) ?
            _setTokenRoyalty(_tokenId, _royaltyAddress, _newRoyalty) :
            _setTokenRoyalty(_tokenId, royaltyAddress, _newRoyalty);
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
        tokenExists(_tokenId) {
            require(_vId < 5, "Must set _vId<5");
            _tokens[_tokenId].validity = _vId;
    }

    /**
     * @dev Allows holder to set back to SVG view after 
     * token has already been upgraded. Flag must be set 
     * back to true for upgraded view to show again.
     */
    function setTokenView(uint256 _tokenId, bool _flag)
        external
        tokenExists(_tokenId) {
            require(_isApprovedOrOwner(msg.sender, _tokenId), "Unauthorized token view setter");
            require(_tokenUpgraded[_tokenId], "Token not yet upgraded");
            require(_tokenUpgraded[_tokenId] != _flag, "Token view already set to this mode");
            _tokenUpgradedView[_tokenId] = _flag;
    }

    /**
     * @dev Allows upgradePrice to be tuned.
     */
    function setTokenUpgradePrice(uint16 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            upgradePrice = _price;
    }

    /**
     * @dev Set token upgrade capability flag.
     */
    function setTokensUpgradable(bool _flag)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            tokensUpgradable = _flag;
    }
}