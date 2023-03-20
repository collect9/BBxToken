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
    function metaNameDesc(uint256 tokenId, uint256 tokenData, string calldata name)
        external view
        returns(bytes memory) {
            bytes6 b6TokenId = Helpers.tokenIdToBytes(tokenId);
            uint256 _genTag = _viewPackedData(tokenData, UPOS_GENTAG, USZ_GENTAG);
            bytes3 bGentag = Helpers.uintToOrdinal(_genTag);

            uint256 _genTush = _viewPackedData(tokenData, UPOS_GENTUSH, USZ_GENTUSH);
            bytes3 bGentush = Helpers.uintToOrdinal(_genTush);

            bytes3 _cntrytag = _vFlags[_viewPackedData(tokenData, UPOS_CNTRYTAG, USZ_CNTRYTAG)];
            bytes3 _cntrytush = _vFlags[_viewPackedData(tokenData, UPOS_CNTRYTUSH, USZ_CNTRYTUSH)];
            uint256 x = _cntrytag[2] == 0x20 ? 0 : 1; // Offset flag


            // b6TokenId in link
            // b7TokenId in name
            bytes memory _datap1 = '{'
                '"external_url":"https://collect9.io/nft/      ",'
                '"name":"Collect9 Physically Redeemable NFT #'
                ;
            bytes memory _datap2 = ' - 3RD Gen '; // Country 2 or 3 length
            bytes memory _datap3 = ' YYY '; // Country 3 length
            // Name
            bytes memory _datap4 = '","description":"'
                'Collect9\'s physically redeemable NFTs contain **100%** of their metadata and SVG images on-chain! '
                'They are some of the most efficient NFTs to exist on Ethereum - offering capabilities far beyond the '
                'standardized ERC721 spec - for nearly the same cost of the basic spec. To see how these NFTs '
                'are innovating, visit the Collect9 website. '
                'This NFT - validated by Ethereum network - certifies ownership and possession rights for the following '
                'physical collectible: one physical vintage Beanie Baby(TM) collectible, uniquely identifiable by the authentication '
                'certificate id (displayed on the NFT\'s SVG image) received from professional authenticators True Blue Beans. '
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

            assembly {
                let dst := add(_datap1, 73)
                mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
                dst := add(_datap1, 103)
                mstore(dst, or(and(mload(dst), not(shl(208, 0xFFFFFFFFFFFF))), b6TokenId))
                dst := add(_datap1, 112)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
                dst := add(_datap1, 116)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
                dst := add(_datap2, 205)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
                dst := add(_datap2, 209)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
                dst := add(add(_datap2, 212), x)
                mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "/"))
                dst := add(add(_datap2, 214), x)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
                dst := add(add(_datap2, 218), x)
                mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
            }
            return bytes.concat(
                _datap1,
                name,
                _datap2
            );
    }

    // /**
    //  * @dev Constructs the json string containing the attributes of the token.
    //  */
    // function metaAttributes(uint256 tokenData)
    //     external view override
    //     returns (bytes memory b) {
    //         (uint256 _bgidx, bytes16 _rclass) = _getRarityTier(
    //             uint256(uint8(_uTokenData>>POS_GENTAG)),
    //             uint256(uint8(_uTokenData>>POS_RARITYTIER)),
    //             uint256(uint8(_uTokenData>>POS_SPECIAL))
    //         );
    //         bytes10 _bgcolor = hex3ToColor[hex3[_bgidx]];

    //         bytes3 _gentag = Helpers.uintToOrdinal(
    //             uint256(uint8(_uTokenData>>POS_GENTAG))
    //         );
    //         bytes3 _gentush = Helpers.uintToOrdinal(
    //             uint256(uint8(_uTokenData>>POS_GENTUSH))
    //         );
    //         bytes3 _cntrytag = _vFlags[uint256(uint8(_uTokenData>>POS_CNTRYTAG))];
    //         bytes3 _cntrytush = _vFlags[uint256(uint8(_uTokenData>>POS_CNTRYTUSH))];
    //         bytes2 _edition = Helpers.remove2Null(bytes2(Helpers.uintToBytes(
    //             uint256(uint8(_uTokenData>>POS_EDITION))
    //         )));
    //         bytes4 __mintId = Helpers.flip4Space(bytes4(Helpers.uintToBytes(
    //             uint256(uint16(_uTokenData>>POS_MINTID))
    //         )));

    //         bytes3 _upgraded = uint256(uint8(_uTokenData>>POS_UPGRADED)) == UPGRADED ? bytes3("YES") : bytes3("NO ");
    //         bytes3 _redeemed = uint256(uint8(_uTokenData>>POS_VALIDITY)) == REDEEMED ? bytes3("YES") : bytes3("NO ");

    //         uint256 _offset = _cntrytag[2] == 0x20 ? 0 : 1;
    //         b = '","attributes":['
    //             '{"trait_type":"Hang Tag Gen","value":"   "},'
    //             '{"trait_type":"Hang Tag Country","value":"   "},'
    //             '{"trait_type":"Hang Combo","value":"       "},'
    //             '{"trait_type":"Tush Tag Gen","value":"   "},'
    //             '{"trait_type":"Tush Tag Country","value":"   "},'
    //             '{"trait_type":"Tush Special","value":"NONE"},'
    //             '{"trait_type":"Tush Combo","value":"            "},'
    //             '{"trait_type":"Hang Tush Combo","value":"                      "},'
    //             '{"trait_type":"C9 Rarity Class","value":"  "},'
    //             '{"display_type":"number","trait_type":"Edition","value":  },'
    //             '{"display_type":"number","trait_type":"Edition Mint ID","value":    },'
    //             '{"trait_type":"Upgraded","value":"   "},'
    //             '{"trait_type":"Background","value":"          "},'
    //             '{"trait_type":"Redeemed","value":"   "}'
    //             ']}';
    //         assembly {
    //             let dst := add(b, 86)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
    //             dst := add(b, 134)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
    //             dst := add(b, 176)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
    //             dst := add(b, 180)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
    //             dst := add(b, 224)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
    //             dst := add(b, 272)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
    //             dst := add(b, 359)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
    //             dst := add(b, 363)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
    //             dst := add(b, 415)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentag))
    //             dst := add(b, 419)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytag))
    //             dst := add(add(b, 422), _offset)
    //             mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), "/"))
    //             dst := add(add(b, 424), _offset)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _gentush))
    //             dst := add(add(b, 428), _offset)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _cntrytush))
    //             dst := add(b, 481)
    //             let mask := shl(240, 0xFFFF)
    //             let srcpart := and(_rclass, mask)
    //             let destpart := and(mload(dst), not(mask))
    //             mstore(dst, or(destpart, srcpart))
    //             dst := add(b, 542)
    //             mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _edition))
    //             dst := add(b, 610)
    //             mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintId))
    //             dst := add(b, 650)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _upgraded))
    //             dst := add(b, 692)
    //             mstore(dst, or(and(mload(dst), not(shl(176, 0xFFFFFFFFFFFFFFFFFFFF))), _bgcolor))
    //             dst := add(b, 739)
    //             mstore(dst, or(and(mload(dst), not(shl(232, 0xFFFFFF))), _redeemed))
    //         }
    //         _checkTushMarker(uint256(uint8(_uTokenData>>POS_MARKERTUSH)), b, _offset);
    //     }
}