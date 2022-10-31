// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./C9MetaData.sol";
import "./C9Shared.sol";
import "./C9SVG.sol";


contract C9Token is ERC721Enumerable, ERC721Burnable, ERC2981, Ownable {
    /**
     * @dev Flag that may enable IPFS artwork versions to be 
     displayed in the future.
     */
    bool public svgOnly = true;
    string baseURI;

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
    uint16[96] private _mintId;

    /**
     * @dev The meta and SVG contracts.
     */
    address public _metaContract = 0xdCd6ea996f3feBC00CF79e1cB88495420AF2332A;
    address public _svgContract = 0xE1A03465DE47cD5D3F4B1fe4aE3b225D3a5f2F1E;
    
    /**
     * @dev The address to send royalties to.
     */
    address public _royaltiesTo = 0xA10cd593d65Ee05e9A140D69c83dfABB925Ec1A3;

    /**
     * @dev The constructor sets the default royalty of the token 
     * to 3.5%.
     */
    constructor() ERC721("Collect9 BBR NFTs", "C9xBB") {
        _setDefaultRoyalty(_royaltiesTo, 350);
    }

    modifier tokenExists(uint256 _tokenId) {
        require(_exists(_tokenId), "QRY NULL TOKEN");
        _;
    }

    /**
     * @dev Required override.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable) {
            super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev The token burning required for the redemption process.
     * Override is because we need to remove tokens[tokenId].
     * Note the `attrComboExists` of the token is not removed, thus 
     * once the `edition` of any burned token cannot be replaced, but 
     * instead will keep incrementing.
     * 
     * Requirements:
     *
     * - `tokenId` must exist.
     * - token burner must be token owner.
     */
    function burn(uint256 tokenId)
        public
        override(ERC721Burnable) {
            require(_isApprovedOrOwner(msg.sender, tokenId), "BURNER NOT APPROVED");
            _burn(tokenId);
            delete(tokens[tokenId]);
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
    function b64Image(uint256 _tokenId)
        public view
        tokenExists(_tokenId)
        returns (string memory) {
            return Base64.encode(bytes(svgImage(_tokenId)));
    }

    /**
     * @dev Contract-level meta data.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    function contractURI()
        public pure
        returns (string memory) {
            return "https://collect9.io/metadata/Collect9RWARBBToken.json";
    }

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function getPhysicalHash(
        C9Shared.TokenInfo calldata _input,
        uint8 _edition
    ) internal pure returns (bytes32) {
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
     * - `_input` royalty is between 1-9.99%.
    */
    function mint1(C9Shared.TokenInfo calldata _input)
        public
        onlyOwner {
            require(_input.tag < 8 && _input.tush < 8, "ERR TAG TUSH");
            require(_input.royalty < 1000, "ERR ROYALTY");
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
                _input.validity, // may not be needed, stored in mapping that will default to false -> automatically becomes valid after block.timestamp + 1 year
                _edition,
                _input.tag,
                _input.tush,
                _input.gentag,
                _input.gentush,
                _input.markertush,
                _input.spec,
                _input.rtier,
                __mintId,
                _input.royalty, // not needed, already stored in setTokenRoyalty -> svg contract can call token contract
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
        public view override(ERC721, ERC721Enumerable, ERC2981)
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
     * json output that includes the SVG image.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
    */
    function tokenURI(uint256 _tokenId)
        public view override
        tokenExists(_tokenId)
        returns (string memory) {
            if (svgOnly) {
                return string(
                    abi.encodePacked(
                        'data:application/json;base64,',
                        Base64.encode(
                            abi.encodePacked(
                                IC9MetaData(_metaContract).metaNameDesc(tokens[_tokenId]),
                                b64Image(_tokenId),
                                IC9MetaData(_metaContract).metaAttributes(tokens[_tokenId])
                            )
                        )
                    )
                );
            }
            else {
                return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(_tokenId))) : ""; //consider updating so metadata remains fixed
            }
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
     * @dev Set SVG flag.
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
    function setTokenRoyalties(uint256 _tokenId, uint96 _newRoyalty)
        external
        onlyOwner
        tokenExists(_tokenId) {
            require(_newRoyalty < 1000, "ROYALTY TOO HIGH"); // Limit max royalty to 10%
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
}