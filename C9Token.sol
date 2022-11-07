// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./utils/Pricer.sol";
import "./C9MetaData.sol";
import "./C9Shared.sol";
import "./C9SVG.sol";


contract C9Token is ERC721Enumerable, ERC2981, Ownable {
    /**
     * @dev Flag that may enable IPFS artwork versions to be 
     displayed in the future.
     */
    bool public tokensUpgradable = false;

    /**
     * @dev Contract level meta data, and svgFlag.
     */
    string _contractURI = "https://collect9.io/metadata/Collect9RWARBBToken.json";
    string public baseURI;
    bool public svgOnly = true;
    
    /**
     * @dev These have to do with a potential token upgrade path.
     * Upgraded involves setting token to point to baseURI and 
     * display.
     */
    address payable Owner;
    mapping(uint256 => bool) tokenUpgraded;
    mapping(uint256 => bool) tokenUpgradedView;
    uint16 upgradePrice = 100;
    event Upgrade(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 indexed price
    );

    /**
     * @dev Structure that holds all of the token info required to 
     * construct the SVG.
     */
    mapping(uint256 => C9Shared.TokenInfo) tokens;

    /**
     * @dev Mapping that checks whether or not some combination of 
     * TokenInfo has already been minted. The bool return is 
     * responsible for determining whether or not to increment 
     * the editionID.
     */
    mapping(bytes32 => bool) attrComboExists;

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
    address public _metaContract;
    address public _svgContract;
    address _priceFeedContract;
    
    /**
     * @dev The address to send royalties to. This is defined so that it 
     * may be changed or updated later on to a non-owner address if
     * desired.
     */
    address _royaltiesTo;

    /**
     * @dev The constructor sets the default royalty of the token 
     * to 5.0%. Owner needs to be set because default owner from 
     * ownable is not payable. All addresses can be updated after 
     * deployment.
     */
    constructor(
        address metaContract,
        address svgContract,
        address priceFeedContract
        )
        ERC721("Collect9 BBR NFTs", "C9xBB") {
            Owner = payable(msg.sender);
            _royaltiesTo = Owner;
            _setDefaultRoyalty(_royaltiesTo, 500);
            // Set default contracts
            _metaContract = metaContract;
            _priceFeedContract = priceFeedContract;
            _svgContract = svgContract;
    }

    modifier tokenExists(uint256 _tokenId) {
        require(_exists(_tokenId), "QRY null token");
        _;
    }

    /**
     * @dev Required override.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721Enumerable) {
            super._beforeTokenTransfer(from, to, tokenId);
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
        public {
            require(_isApprovedOrOwner(msg.sender, _tokenId), "BURNER not approved");
            _burn(_tokenId);
            delete(tokens[_tokenId]);
            delete(tokenUpgraded[_tokenId]);
            delete(tokenUpgradedView[_tokenId]);
            _resetTokenRoyalty(_tokenId);
    }

    /**
     * @dev Testing function only, remove for release.
     */
    function burnAll()
        public
        onlyOwner {
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
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    function contractURI()
        public view
        returns (string memory) {
            return _contractURI;
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
        onlyOwner {
            //require(_input.tag < 8 && _input.tush < 8, "ERR tag tush");
            require(_input.royalty < 1000, "ERR royalty");
            uint256 _uid = uint256(_input.id); 

            uint8 _edition = _input.edition;
            if (_edition == 0) {
                bytes32 _data;
                for (uint8 i=1; i<100; i++) {
                    _data = getPhysicalHash(_input, i);
                    if (!attrComboExists[_data]) {
                        _edition = i;
                        break;
                    }
                }
            }

            uint16 __mintId = _input.mintid == 0 ? _mintId[_edition] + 1 : _input.mintid;
            tokens[_uid] = C9Shared.TokenInfo(
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

            _setTokenRoyalty(_uid, _royaltiesTo, _input.royalty);
            _mint(msg.sender, _uid);
            
            attrComboExists[getPhysicalHash(_input, _edition)] = true;
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
        onlyOwner {
            for (uint8 i; i<N; i++) {
                mint1(_input[i]);
            }
    }

    /**
     * @dev Required override.
    */
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721Enumerable, ERC2981)
        returns (bool) {
            return super.supportsInterface(interfaceId);
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
            return IC9SVG(_svgContract).returnSVG(ownerOf(_tokenId), tokens[_tokenId]);
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
            bool upgraded = tokenUpgraded[_tokenId];
            bytes memory meta = IC9MetaData(_metaContract).metaNameDesc(tokens[_tokenId]);
            bytes memory attributes = IC9MetaData(_metaContract).metaAttributes(tokens[_tokenId], upgraded);
            if (!svgOnly && upgraded && tokenUpgradedView[_tokenId]) {
                return string(
                    abi.encodePacked(
                        'data:application/json;base64,',
                        Base64.encode(
                            abi.encodePacked(
                                meta,
                                ',"image":"',
                                baseURI, Strings.toString(_tokenId), '.png',
                                attributes
                            )
                        )
                    )
                );
            }
            else {
                return string(
                    abi.encodePacked(
                        'data:application/json;base64,',
                        Base64.encode(
                            abi.encodePacked(
                                meta,
                                ',"image":"data:image/svg+xml;base64,',
                                b64SVGImage(_tokenId),
                                attributes
                            )
                        )
                    )
                );
            }
    }

    /**
     * @dev Allows the token holder to upgrade their token.
     How to handle is user wants to still display SVG???
     */
    function upgradeToken(uint256 _tokenId)
        public payable
        tokenExists(_tokenId) {
            require(!tokensUpgradable, "Upgrades are currently not enabled");
            require(_isApprovedOrOwner(msg.sender, _tokenId), "UPGRADER unauthorized");
            require(!tokenUpgraded[_tokenId], "Token already upgraded");
            require(msg.value == IEthPricer(_priceFeedContract).getTokenETHPrice(upgradePrice), "Wrong amount of ETH");
            (bool success,) = Owner.call{value: msg.value}("");
            require(success, "Failed to send ETH");
            tokenUpgraded[_tokenId] = true;
            tokenUpgradedView[_tokenId] = true;
            emit Upgrade(msg.sender, _tokenId, upgradePrice);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`.
     */
    function _baseURI()
        internal view override
        returns (string memory) {
            return baseURI;
    }

     /**
     * @dev Updates the contractURI.
     */
    function setContractUri(string calldata _newContractURI)
        external
        onlyOwner {
            _contractURI = _newContractURI;
    }

    /**
     * @dev Updates the baseURI.
     * By default this contract will load SVGs from another contract, 
     * but if a future upgrade allows for artwork on IPFS, the 
     * contract will need to set the IPFS location.
     */
    function setBaseUri(string calldata _newBaseURI)
        external
        onlyOwner {
            baseURI = _newBaseURI;
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setMetaContract(address _address)
        external
        onlyOwner {
            _metaContract = _address;
    }

    /**
     * @dev Updates the meta data contract address.
     * This will be most useful when trying to make a generic 
     * SVG template that will include other collectible classes.
     */
    function setPriceFeedContract(address _address)
        external
        onlyOwner {
            _priceFeedContract = _address;
    }

    /**
     * @dev Allows the contract owner to update the royalties 
     * receving address.
     */
    function setRoyaltiesAddress(address _address)
        external
        onlyOwner {
            _royaltiesTo = _address;
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
        onlyOwner {
            _svgContract = _address;
    }

    /**
     * @dev Set SVG flag to either display on-chain SVG (true) or IPFS 
     * version (false). If set to true, it is still possible 
     * to retrieve the SVG image by calling svgImage(_tokenId).
     */
    function setSVGFlag(bool _flag)
        external
        onlyOwner {
            svgOnly = _flag;
    }

    /**
     * @dev Allows the contract owner to update the royalties 
     * per token basis, within limits.
     * This will be useful in the future for potentially having 
     * royalty free weekends, etc, as well as fine tuning the 
     * royalty income model.
     */
    function setTokenRoyalty(uint256 _tokenId, uint96 _newRoyalty)
        external
        onlyOwner
        tokenExists(_tokenId) {
            require(_newRoyalty < 1000, "Royalty too high"); // Limit max royalty to 10%
            _setTokenRoyalty(_tokenId, _royaltiesTo, _newRoyalty);
    }

    /**
     * @dev Updates the token validity status.
     * Validity will not prevent or pause transfers. It is 
     * only a display flag to let users know of the token's 
     * status.
     */
    function setTokenValidity(uint256 _tokenId, uint8 _vFlag)
        external
        onlyOwner
        tokenExists(_tokenId) {
            tokens[_tokenId].validity = _vFlag;
    }

    /**
     * @dev Allows holder to set back to SVG view after 
     * token has already been upgraded. Flag must be set 
     * back to true for upgraded view to show again.
     */
    function setTokenView(uint256 _tokenId, bool _flag)
        external
        tokenExists(_tokenId) {
            require(_isApprovedOrOwner(msg.sender, _tokenId), "VIEWER not approved");
            require(tokenUpgraded[_tokenId], "Token not yet upgraded");
            tokenUpgradedView[_tokenId] = _flag;
    }

    /**
     * @dev Allows upgradePrice to be modified and tuned.
     */
    function setTokenUpgradePrice(uint16 _price)
        external
        onlyOwner {
            upgradePrice = _price;
    }

    /**
     * @dev Set token upgrade capability flag.
     */
    function setUpgradeFlag(bool _flag)
        external
        onlyOwner {
            tokensUpgradable = _flag;
    }
}