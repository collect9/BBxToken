// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./utils/Base64.sol";
import "./utils/Helpers.sol";
import "./C9SVGShare.sol";
import "./C9SVG.sol";

contract C9BBToken is ERC721, ERC721Burnable, ERC2981, Ownable, C9SVGShare {
    mapping(uint256 => IC9SVG.TokenInfo) tokens;
    mapping(bytes32 => bool) attrComboExists;
    uint16[99] private _mintId;
    address private _royaltiesto = 0xA10cd593d65Ee05e9A140D69c83dfABB925Ec1A3;

    constructor() ERC721("Collect9 RWAR:BB Tokens", "C9xBB") {
        _setDefaultRoyalty(_royaltiesto, 350);
        for (uint8 i; i<99; i++) {
            _mintId[i] = 1;
        }
    }

    modifier _tokenExists(uint256 _tokenId, string memory message) {
        require(_exists(_tokenId), message);
        _;
    }

    /**
     * @dev The token burning required for the redemption process. 
     * Note the `attrComboExists` of the token is not removed, thus 
     * once the `edition` of any burned token cannot be replaced, but 
     * instead will keep incrementing.
     * 
     * Requirements:
     *
     * - `tokenId` must exist.
     * - token burner must be token owner.
     */
    function burn(uint256 tokenId) public override(ERC721Burnable) {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "BURNER NOT APPROVED");
        _burn(tokenId);
        delete(tokens[tokenId]);
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
    function b64Image(
        uint256 _tokenId
    ) public view _tokenExists(_tokenId, "B64 QRY NULL TOKEN") returns (string memory) {
        return Base64.encode(bytes(svgImage(_tokenId)));
    }

    /**
     * @dev Contract-level meta data.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    function contractURI() public pure returns (string memory) {
        return "https://collect9.io/metadata/Collect9RWARBBToken.json";
    }

    /**
     * @dev Returns a unique hash depending on certain token `_input` attributes. 
     * This helps keep track the `_edition` number of a particular set of attributes. 
     * Note that if the token is burned, the edition cannot be replaced but 
     * instead will keep incrementing.
     */
    function getPhysicalHash(
        IC9SVG.TokenInfo calldata _input,
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
     * @dev Constructs the json string containing the attributes of the token.
     * Note this continues and finishes off in `metaAttributesCloser()`.
     */
    function metaAttributes(uint256 _tokenId) internal view returns (bytes memory b) {
        bytes2[12] memory rclasses = [bytes2("T0"), "T1", "T2", "T3", "T4", "T5", "T6", "T7", "S0", "S1", "S2", "S3"];
        bytes2 _rclass = rclasses[tokens[_tokenId].rtier];
        bytes3 _gentag = Helpers.uintToOrdinal(tokens[_tokenId].gentag);
        bytes3 _cntrytag = Helpers.checkTagForNulls(_vFlags[tokens[_tokenId].tag]);
        bytes3 _gentush = Helpers.uintToOrdinal(tokens[_tokenId].gentush);
        bytes3 _cntrytush = _vFlags[tokens[_tokenId].tush];
        bytes2 _edition = Helpers.remove2Null(bytes2(Helpers.uintToBytes(tokens[_tokenId].edition)));
        bytes1 _slash = bytes1("/");
        bytes4 __mintId = Helpers.flip4Space(bytes4(Helpers.uintToBytes(tokens[_tokenId].mintid)));
        uint8 x = _cntrytag[2] == 0x20 ? 0 : 1;
        b = '","attributes":[{"trait_type":"Hang Tag Gen","value":"   "},{"trait_type":"Hang Tag Country","value":"   "},{"trait_type":"Hang Combo","value":"       "},{"trait_type":"Tush Tag Gen","value":"   "},{"trait_type":"Tush Tag Country","value":"   "},{"trait_type":"Tush Special","value":"NONE"},{"trait_type":"Tush Combo","value":"            "},{"trait_type":"Hang Tush Combo","value":"                     "},{"trait_type":"C9 Rarity Class","value":"  "},{"display_type":"number","trait_type":"Edition","value":  },{"display_type":"number","trait_type":"Edition Mint ID","value":    },{"trait_type":"Background","value":"';
        assembly {
            let dst := add(b, 86)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
            dst := add(b, 134)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            dst := add(b, 176)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
            dst := add(b, 180)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            dst := add(b, 224)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
            dst := add(b, 272)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
            dst := add(b, 359)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
            dst := add(b, 363)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
            dst := add(b, 415)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
            dst := add(b, 419)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            dst := add(add(b, 422), x)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _slash))
            dst := add(add(b, 424), x)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
            dst := add(add(b, 428), x)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
            dst := add(b, 480)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _rclass))
            dst := add(b, 541)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _edition))
            dst := add(b, 609)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintId))
        }
        uint8 _markerid = tokens[_tokenId].markertush;
        if (_markerid > 0) {
            bytes4 _markertush = _vMarkers[_markerid-1];
            assembly {
                let dst := add(b, 316)
                mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
                dst := add(b, 367)
                mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
                dst := add(add(b, 432), x)
                mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
            }
        }
        b = metaAttributesCloser(_tokenId, b);
    }

    /**
     * @dev Finishes off the bytes string started in metaAttributes that is otherwise 
     * unable to fit due to stack to deep.
     */
    function metaAttributesCloser(uint256 _tokenId, bytes memory b) internal view returns (bytes memory) {
        bytes[11] memory bgs = [bytes("ONYX"), // T1 (pre)
            "GOLD", // T2-T3
            "SILVER", // T2-T4
            "BRONZE", // T2-T5
            "AMETHYST", // S2
            "RUBY", // T1 (emb)
            "EMERALD", // S1
            "SAPPHIRE", // RES
            "DIAMOND", // RES
            "CARDBOARD", // T6+
            "NEBULA" // S0
        ];
        return bytes.concat(b, bgs[tokens[_tokenId].spec], '"}]}');
    }
    
    /**
     * @dev Constructs the json string portion containing the external_url, description, 
     * and name parts.
     */
    function metaNameDesc(uint256 _tokenId) internal view returns(bytes memory) {
        bytes6 _id = Helpers.tokenIdToBytes(tokens[_tokenId].id);
        bytes3 _gentag = Helpers.uintToOrdinal(tokens[_tokenId].gentag);
        bytes3 _cntrytag = Helpers.checkTagForNulls(_vFlags[tokens[_tokenId].tag]);
        bytes3 _gentush = Helpers.uintToOrdinal(tokens[_tokenId].gentush);
        bytes3 _cntrytush = _vFlags[tokens[_tokenId].tush];
        bytes1 _slash = bytes1("/");
        uint8 x = _cntrytag[2] == 0x20 ? 0 : 1;

        bytes memory _name = bytes(tokens[_tokenId].name);
        bytes memory _datap1 = '{"external_url":"https://collect9.io/nft/      ","name":"Collect9 NFT #       -         ';
        bytes memory _datap2 = ' ","description":"NFT certified ownership and possession rights for the following physical collectible: (1x qty) [                  ';
        bytes memory _datap3 = '] Beanie Baby(TM) professionally authenticated museum quality (MQ), uniquely identifiable by the authentication certificate id containing the series of numbers: XXXXXX. Redemption conditions apply. Visit the [Collect9 website](https://collect9.io) for details.","image":"data:image/svg+xml;base64,';
        assembly {
            let dst := add(_datap1, 73)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
            dst := add(_datap1, 103)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
            dst := add(_datap1, 112)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
            dst := add(_datap1, 116)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            dst := add(_datap2, 146)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
            dst := add(_datap2, 150)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
            dst := add(add(_datap2, 153), x)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _slash))
            dst := add(add(_datap2, 155), x)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
            dst := add(add(_datap2, 159), x)
            mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
            dst := add(_datap3, 193)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), _id))
        }
        return bytes.concat(
            _datap1,
            _name,
            _datap2,
            _name,
            _datap3
        );
    }

    /**
     * @dev Helps makes the overall minting process faster and cheaper 
     * on average per mint.
    */
    function mint5Bulk(address recipient, IC9SVG.TokenInfo[5] calldata _input) external onlyOwner {
        for (uint8 i; i<5; i++) {
            mintC9Token(recipient, _input[i]);
        }
    }
    function mint10Bulk(address recipient, IC9SVG.TokenInfo[10] calldata _input) external onlyOwner {
        for (uint8 i; i<10; i++) {
            mintC9Token(recipient, _input[i]);
        }
    }
    function mint20Bulk(address recipient, IC9SVG.TokenInfo[20] calldata _input) external onlyOwner {
        for (uint8 i; i<20; i++) {
            mintC9Token(recipient, _input[i]);
        }
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
    function mintC9Token(address recipient, IC9SVG.TokenInfo calldata _input) public onlyOwner {
        require(_input.tag < 7 && _input.tush < 7, "BAD FLAG");
        require(_input.royalty > 99 && _input.royalty < 1000, "BAD ROYALTY");
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

        uint16 __mintId = _input.mintid == 0 ? _mintId[_edition] : _input.mintid;
        _setTokenRoyalty(_uid, _royaltiesto, _input.royalty);

        tokens[_uid] = IC9SVG.TokenInfo(
            _edition,
            _input.tag,
            _input.tush,
            _input.gentag,
            _input.gentush,
            _input.markertush,
            _input.spec,
            _input.rtier,
            __mintId,
            _input.id,
            uint56(block.timestamp),
            _input.royalty,
            _input.name,
            _input.qrdata,
            _input.bardata
        );

        _mint(recipient, _uid);
        
        attrComboExists[getPhysicalHash(_input, _edition)] = true;
        if (_input.mintid == 0) {
            _mintId[_edition] += 1;
        }
    }

    /**
     * @dev Required override.
    */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
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
    function svgImage(
        uint256 _tokenId
    ) public view _tokenExists(_tokenId, "SVG QRY NULL TOKEN") returns (string memory) {
        address _dc = 0xF382df82D2e1e9d5DA47Af0C8a1fa96d367C5548;
        return IC9SVG(_dc).returnSVG(ownerOf(_tokenId), tokens[_tokenId]);
    }

    /**
     * @dev Required override that returns fully onchain constructed 
     * json output that includes the SVG image.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
    */
    function tokenURI(
        uint256 _tokenId
    ) public view override _tokenExists(_tokenId, "URI QRY NULL TOKEN") returns (string memory) {
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    abi.encodePacked(
                        metaNameDesc(_tokenId),
                        b64Image(_tokenId),
                        metaAttributes(_tokenId)
                    )
                )
            )
        );
    }
}