// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Errors.sol";
import "./abstract/C9Shared.sol";
import "./interfaces/IC9MetaData.sol";
import "./interfaces/IC9SVG2.sol";
import "./interfaces/IC9Token.sol";

import "./utils/Base64.sol";
import "./utils/C9Context.sol";
import "./utils/Helpers.sol";

contract C9MetaData is IC9MetaData, C9Shared, C9Context {

    address private _owner;
    address public contractSVG;
    address public immutable contractToken;

    constructor (address _contractSVG, address _contractToken) {
        _owner = msg.sender;
        contractSVG = _contractSVG;
        contractToken = _contractToken;
    }

    function _imgMetaData(uint256 tokenId, uint256 ownerData, uint256 tokenData)
    private view
    returns (bytes memory) {
        uint256 viewIndex = _currentVId(tokenData) >= REDEEMED ? URI1 : URI0;
        bytes memory image = abi.encodePacked(
            ',"image":"',
            IC9Token(contractToken).baseURIArray(viewIndex),
            Helpers.tokenIdToBytes(tokenId),
            '.png"}'
        );
        return bytes.concat(
            _metaDesc(tokenId),
            _metaAttributes(tokenData, ownerData),
            image
        );
    }

    /**
     * @dev Constructs the json string containing the attributes of the token.
     * Bytes2, 3, etc are reused to save on stack space.
     */
    function _metaAttributes(uint256 data, uint256 ownerData)
    private view
    returns (bytes memory b) {
        uint256 mask;
        b = '","attributes":['
            '{"trait_type":"Hang Tag","value":"       "},'
            '{"trait_type":"Hang Tag Gen","value":  },'
            '{"trait_type":"Hang Tag Country","value":"   "},'
            '{"trait_type":"Tush Tag","value":"            "},'
            '{"trait_type":"Tush Tag Gen","value":  },'
            '{"trait_type":"Tush Tag Country","value":"   "},'
            '{"trait_type":"Tush Tag Modifier","value":"NORM"},'
            '{"trait_type":"Full Tag Combo","value":"                      "},'
            '{"trait_type":"Mint Date","display_type":"date","value":          },'
            '{"trait_type":"Upgraded","value":"   "},'
            '{"trait_type":"Redeemed","value":"   "},'
            '{"trait_type":"C9 Rarity Tier","value": ,"max_value":9},'
            '{"trait_type":"C9 Type Class","value":" "},'
            '{"trait_type":"C9 Class Rarity Combo","value":"  "},'
            '{"trait_type":"Background","value":"          "},'
            '{"trait_type":"Edition","display_type":"number","value":  ,"max_value":99},'
            '{"trait_type":"Edition Mint Id","display_type":"number","value":    ,"max_value":    },'
            '{"trait_type":"Votes","display_type":"boost_number","value":  ,"max_value":15},'
            '{"trait_type":"Transfer Count","value":       ,"max_value":1048575},'
            '{"trait_type":"Hang Tag Generation","value":"   "},'
            '{"trait_type":"Tush Tag Generation","value":"   "}],';

        // 1. All 2 byte attributes
    
        // Edition number
        uint256 edition = _viewPackedData(data, UPOS_EDITION, USZ_EDITION);
        bytes2 attribute2 = Helpers.remove2Null(
            bytes2(Helpers.uintToBytes(
                edition
            ))
        );
        assembly {
            mask := not(shl(240, 0xFFFF))
            let dst := add(b, 838)
            mstore(dst, or(and(mload(dst), mask), attribute2))
        }

        // Hang tag gen number
        attribute2 = Helpers.remove2Null(
            bytes2(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG)
            ))
        );
        assembly {
            let dst := add(b, 129)
            mstore(dst, or(and(mload(dst), mask), attribute2))
        }

        // Tush tag gen number
        attribute2 = Helpers.remove2Null(
            bytes2(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH)
            ))
        );
        assembly {
            let dst := add(b, 267)
            mstore(dst, or(and(mload(dst), mask), attribute2))
        }

        // Number of votes
        attribute2 = Helpers.remove2Null(
            bytes2(Helpers.uintToBytes(
                _viewPackedData(ownerData, MPOS_VOTES, MSZ_VOTES)
            ))
        );
        assembly {
            let dst := add(b, 1004)
            mstore(dst, or(and(mload(dst), mask), attribute2))
        }

        // 2. All 3 byte attributes

        // Country tag
        bytes3 attribute3 = bytes3(_getFlagText(_viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG)));
        uint256 _offset = attribute3[2] == 0x20 ? 0 : 1;
        assembly {
            mask := not(shl(232, 0xFFFFFF))
            let dst := add(b, 86)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
            dst := add(b, 175)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
            dst := add(b, 413)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
        }
        
        // Country tush
        attribute3 = bytes3(_getFlagText(_viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH)));
        assembly {
            let dst := add(b, 219)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
            dst := add(b, 313)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
            dst := add(add(b, 422), _offset)
            mstore(dst, or(and(mload(dst), mask), and(attribute3, not(mask))))
        }

        // Hang tag gen ordinal
        attribute3 = Helpers.uintToOrdinal(
            _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG)
        );
        assembly {
            let dst := add(b, 82)
            mstore(dst, or(and(mload(dst), mask), attribute3))
            dst := add(b, 409)
            mstore(dst, or(and(mload(dst), mask), attribute3))
            dst := add(b, 1136)
            mstore(dst, or(and(mload(dst), mask), attribute3))
        }

        // Tush tag gen ordinal
        attribute3 =  Helpers.uintToOrdinal(
            _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH)
        );
        assembly {
            let dst := add(b, 215)
            mstore(dst, or(and(mload(dst), mask), attribute3))
            dst := add(add(b, 418), _offset)
            mstore(dst, or(and(mload(dst), mask), attribute3))
            dst := add(b, 1187)
            mstore(dst, or(and(mload(dst), mask), attribute3))
        }

        // Upgraded status
        attribute3 = (
            ownerData>>MPOS_UPGRADED & BOOL_MASK
        ) == UPGRADED ? bytes3("YES") : bytes3("NO ");
        assembly {
            let dst := add(b, 536)
            mstore(dst, or(and(mload(dst), mask), attribute3))
        }

        // Redeemed status
        attribute3 = _viewPackedData(
            ownerData,
            MPOS_VALIDITY,
            MSZ_VALIDITY
        ) == REDEEMED ? bytes3("YES") : bytes3("NO ");
        assembly {
            let dst := add(b, 576)
            mstore(dst, or(and(mload(dst), mask), attribute3))
        }

        // 3. All 4 byte attributes

        // Edition mint id
        bytes4 attribute4 = Helpers.remove4Null(
            bytes4(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_EDITION_MINT_ID, USZ_EDITION_MINT_ID)
            ))
        );
        assembly {
            mask := not(shl(224, 0xFFFFFFFF))
            let dst := add(b, 921)
            mstore(dst, or(and(mload(dst), mask), attribute4))
        }

        // Max mint id (so far) of this edition
        attribute4 = Helpers.remove4Null(
            bytes4(Helpers.uintToBytes(
                IC9Token(contractToken).getEditionMaxMintId(edition)
            ))
        );
        assembly {
            let dst := add(b, 938)
            mstore(dst, or(and(mload(dst), mask), attribute4))
        }

        // Marker tush if present
        uint256 _markerTush = _viewPackedData(data, UPOS_MARKERTUSH, USZ_MARKERTUSH);
        if (_markerTush > 0 && _markerTush < 5) {
            // attribute4 = _vMarkers[_markerTush-1];
            attribute4 = bytes4(_getMarkerText(_markerTush));
            assembly {
                let dst := add(b, 223)
                mstore(dst, or(and(mload(dst), mask), and(attribute4, not(mask))))
                dst := add(b, 362)
                mstore(dst, or(and(mload(dst), mask), and(attribute4, not(mask))))
                dst := add(add(b, 426), _offset)
                mstore(dst, or(and(mload(dst), mask), and(attribute4, not(mask))))
            }
        }

         // 4. Remaining attributes

        // Type class and rarity tier
        (uint256 _bgidx, bytes16 _rclass) = _getRarityTier(
            _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG),
            _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER),
            _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL)
        );

        // Background
        bytes10 attribute10 = _getColorText(_bgidx);
        assembly {
            mask := not(shl(176, 0xFFFFFFFFFFFFFFFFFFFF))
            let dst := add(b, 769)
            mstore(dst, or(and(mload(dst), mask), attribute10))
        }

        // Minting timestamp
        attribute10 = bytes10(Helpers.uintToBytes(
            _viewPackedData(data, UPOS_MINTSTAMP, USZ_TIMESTAMP)
        ));
        assembly {
            let dst := add(b, 490)
            mstore(dst, or(and(mload(dst), mask), attribute10))
        }
        
        // Transfer counter
        bytes7 bXferCounter = Helpers.remove7Null(
            bytes7(Helpers.uintToBytes(
                _viewPackedData(ownerData, MPOS_XFER_COUNTER, MSZ_XFER_COUNTER)
            ))
        );
        assembly {
            let dst := add(b, 1062)
            mstore(dst, or(and(mload(dst), not(shl(200, 0xFFFFFFFFFFFFFF))), bXferCounter))
        }

        // Rarity tier
        bytes1 attribute1 = _rclass[1];
        assembly {
            mask := not(shl(248, 0xFF))
            let dst := add(add(b, 416), _offset)
            mstore(dst, or(and(mload(dst), mask), "/"))
            dst := add(b, 621)
            mstore(dst, or(and(mload(dst), mask), attribute1))
            dst := add(b, 729)
            mstore(dst, or(and(mload(dst), mask), attribute1))
        }

        // Type class
        attribute1 = _rclass[0];
        assembly {
            let dst := add(b, 677)
            mstore(dst, or(and(mload(dst), mask), attribute1))
            dst := add(b, 728)
            mstore(dst, or(and(mload(dst), mask), attribute1))
        }  
    }

    /**
     * @dev Constructs the json string portion containing the external_url, description, 
     * and name parts.
     */
    function _metaDesc(uint256 tokenId)
    private pure
    returns(bytes memory) {
        bytes6 b6TokenId = Helpers.tokenIdToBytes(tokenId);

        bytes memory _datap1 = '{'
            '"external_url":"https://collect9.io/nft/      ",'
            '"name":"Collect9 Physically Redeemable NFT #'
            ;
        bytes memory _datap2 = '","description":"'
            'Collect9\'s physically redeemable NFTs contain **100%** of their metadata and SVG images on-chain! '
            'They are some of the most efficient NFTs to exist on Ethereum - offering capabilities far beyond the '
            'standardized ERC721 spec - for nearly the same cost of the basic spec. To see how these NFTs '
            'are innovating, visit the Collect9 website. '
            'This NFT - validated by Ethereum network - certifies ownership and possession rights for the following '
            'physical collectible: one physical vintage Beanie Baby(TM) collectible, uniquely identifiable by the authentication '
            'certificate id 0';
        bytes memory _datap3 = '' 
            ' (also displayed on the NFT\'s SVG image) received from professional authenticators True Blue Beans. '
            'It has been given the highest condition rating: mint-with-mint-tag museum-quality (MWMT MQ). '
            'Visit the NFT\'s landing page for a more detailed description of the physical collectible including '
            'pictures, by using a  micro QR code reader on the NFT\'s SVG image QR code. '
            'Redemption conditions apply - please visit the [Collect9 website](https://collect9.io) for the full details. '
            'Collect9\'s NFTs may be redeemed through a 100% on-chain process that involves digital signatures for '
            'two-step verification. Once the NFT is redeemed, it becomes locked to the redeemer\'s address and displays '
            'a status of *DEAD* >> REDEEMED. The redeemer\'s account will still maintain any votes the NFT holds. '
            'Redeemed NFTs may be burned, albeit at the loss of its votes. '
            'Prior to any offers or purchases, please refresh this NFT\'s metadata on this marketplace to ensure its '
            'latest status is *VALID*. If an *INVALID* status displays, it must be corrected to *VALID* for the token '
            'to be eligible for redemption.';

        // String representation of tokenId without null bytes
        bytes memory sTokenId;
        uint256 sOffset;
        if (tokenId > 10**5) {
            sTokenId = new bytes(6);
        }
        else {
            sTokenId = new bytes(5);
            sOffset = 1;
        }
        for (uint256 i; i<sTokenId.length;) {
            sTokenId[i] = b6TokenId[sOffset];
            unchecked {++i; ++sOffset;}
        }

        assembly {
            let dst := add(_datap1, 73)
            mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
        }

        return bytes.concat(
            _datap1,
            sTokenId,
            _datap2,
            sTokenId,
            _datap3
        );
    }

    function _svgMetaData(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    private view
    returns (bytes memory) {
        return bytes.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes.concat(
                    _metaDesc(tokenId),
                    _metaAttributes(tokenData, ownerData),
                    '"image":"data:image/svg+xml;base64,',
                    b64Image(tokenId, ownerData, tokenData, codeData),
                    '"}'
                )
            )
        );
    }

    function b64Image(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    public view
    override
    returns (bytes memory) {
        return Base64.encode(svgImage(tokenId, ownerData, tokenData, codeData));
    }

    function metaData(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    external view
    override
    returns (bytes memory) {
        // If SVG only, return SVG
        if (IC9Token(contractToken).svgOnly()) return _svgMetaData(tokenId, ownerData, tokenData, codeData);
        // If upgraded, but not set to external view, return SVG
        bool _externalView = (tokenData>>MPOS_DISPLAY & BOOL_MASK) == EXTERNAL_IMG;
        if (!_externalView) return _svgMetaData(tokenId, ownerData, tokenData, codeData); 
        // If upgraded and set to external, return external image
        return _imgMetaData(tokenId, ownerData, tokenData);
    }

    /**
     * @dev Sets the SVG display contract address.
     */
    function setContractSVG(address _contractSVG)
    external {
        if (msg.sender != _owner) {
            revert Unauthorized();
        }
        contractSVG = _contractSVG;
    }

    function svgImage(uint256 tokenId, uint256 ownerData, uint256 tokenData, uint256 codeData)
    public view
    override
    returns (bytes memory) {
        return IC9SVG(contractSVG).svgImage(tokenId, ownerData, tokenData, codeData);
    }
}