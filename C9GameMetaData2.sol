// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./abstract/C9Shared.sol";
import "./interfaces/IC9MetaData.sol";

import "./utils/C9Context.sol";
import "./utils/Helpers.sol";

contract C9MetaData is C9Shared, C9Context {
    /**
     * @dev Moved because metaAttributes was getting a stack 
     * too deep error with this portion of the code included.
     */
    function _checkTushMarker(uint256 _markerTush, bytes memory b, uint256 _offset)
        private view {
            if (_markerTush > 0 && _markerTush < 5) {
                bytes4 _markertush = _vMarkers[_markerTush-1];
                assembly {
                    let dst := add(b, 316)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
                    dst := add(b, 367)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
                    dst := add(add(b, 432), _offset)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), _markertush))
                }
            }
    }

    /**
     * @dev Constructs the json string portion containing the external_url, description, 
     * and name parts.
     */
    function metaNameDesc(uint256 tokenId)
        external pure
        returns(string memory) {
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

            return string(bytes.concat(
                _datap1,
                sTokenId,
                _datap2,
                sTokenId,
                _datap3
            ));
    }

    /**
     * @dev Constructs the json string containing the attributes of the token.
     */
    function metaAttributes(uint256 data, uint256 ownerData)
        external view
        returns (bytes memory b) {
            b = '","attributes":['
                '{"trait_type":"Hang Tag Gen","value":"   "},'
                '{"trait_type":"Hang Tag Country","value":"   "},'
                '{"trait_type":"Hang Combo","value":"       "},'
                '{"trait_type":"Tush Tag Gen","value":"   "},'
                '{"trait_type":"Tush Tag Country","value":"   "},'
                '{"trait_type":"Tush Special","value":"NONE"},'
                '{"trait_type":"Tush Combo","value":"            "},'
                '{"trait_type":"Hang Tush Combo","value":"                      "},'
                '{"trait_type":"C9 Rarity Class","value":"  "},'
                '{"display_type":"number","trait_type":"Edition","value":  },'
                '{"display_type":"number","trait_type":"Edition Mint ID","value":    },'
                '{"trait_type":"Upgraded","value":"   "},'
                '{"trait_type":"Background","value":"          "},'
                '{"trait_type":"Redeemed","value":"   "},'
                '{"display_type":"boost_number","trait_type":"Aqua Power","value":  },'
                ']}';

            // 1. All the 3 byte attributes
            
            bytes3 attribute3 = Helpers.uintToOrdinal(
                _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG)
            );
            assembly {
                let dst := add(b, 86)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 176)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 415)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            attribute3 = _vFlags[_viewPackedData(data, UPOS_CNTRYTAG, USZ_CNTRYTAG)];
            uint256 _offset = attribute3[2] == 0x20 ? 0 : 1;
            assembly {
                let dst := add(b, 134)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 180)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 419)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            attribute3 =  Helpers.uintToOrdinal(
                _viewPackedData(data, UPOS_GENTUSH, USZ_GENTUSH)
            );
            assembly {
                let dst := add(b, 224)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 359)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(add(b, 424), _offset)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            attribute3 = _vFlags[_viewPackedData(data, UPOS_CNTRYTUSH, USZ_CNTRYTUSH)];
            assembly {
                let dst := add(b, 272)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(b, 363)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
                dst := add(add(b, 428), _offset)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            attribute3 = ownerData>>MPOS_UPGRADED & BOOL_MASK == UPGRADED ? bytes3("YES") : bytes3("NO ");
            assembly {
                let dst := add(b, 650)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            attribute3 = _viewPackedData(ownerData, MPOS_VALIDITY, MSZ_VALIDITY) == REDEEMED ? bytes3("YES") : bytes3("NO ");
            assembly {
                let dst := add(b, 739)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), attribute3))
            }

            // 2. All the 4 byte attributes

            bytes4 attribute4 = Helpers.flip4Space(bytes4(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_EDITION_MINT_ID, USZ_EDITION_MINT_ID)
            )));
            assembly {
                let dst := add(b, 610)
                mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), attribute4))
            }

            uint256 _markerTush = _viewPackedData(data, UPOS_MARKERTUSH, USZ_MARKERTUSH);
            if (_markerTush > 0 && _markerTush < 5) {
                attribute4 = _vMarkers[_markerTush-1];
                assembly {
                    let dst := add(b, 316)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), attribute4))
                    dst := add(b, 367)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), attribute4))
                    dst := add(add(b, 432), _offset)
                    mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), attribute4))
                }
            }

            // 3. Remaining attributes

            (uint256 _bgidx, bytes16 rclass) = _getRarityTier(
                _viewPackedData(data, UPOS_GENTAG, USZ_GENTAG),
                _viewPackedData(data, UPOS_RARITYTIER, USZ_RARITYTIER),
                _viewPackedData(data, UPOS_SPECIAL, USZ_SPECIAL)
            );
            bytes10 bgcolor = hex3ToColor[hex3[_bgidx]];
            bytes2 edition = Helpers.remove2Null(bytes2(Helpers.uintToBytes(
                _viewPackedData(data, UPOS_EDITION, USZ_EDITION)
            )));

            assembly {
                let dst := add(add(b, 422), _offset)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "/"))
                dst := add(b, 481)
                let mask := shl(240, 0xFFFF)
                let srcpart := and(rclass, mask)
                let destpart := and(mload(dst), not(mask))
                mstore(dst, or(destpart, srcpart))
                dst := add(b, 542)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), edition))
                dst := add(b, 692)
                mstore(dst, or(and(mload(dst), not(shl(176, 0xFFFFFFFFFFFFFFFFFFFF))), bgcolor))
            }
        }
}