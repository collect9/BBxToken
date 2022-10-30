// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import "./utils/Helpers.sol";
import "./C9Shared.sol";


interface IC9MetaData {
    function metaNameDesc(C9Shared.TokenInfo calldata token) external view returns(bytes memory);
    function metaAttributes(C9Shared.TokenInfo calldata token) external view returns (bytes memory b);
}

contract C9MetaData is C9Shared {
    /**
     * @dev Constructs the json string portion containing the external_url, description, 
     * and name parts.
     */
    function metaNameDesc(TokenInfo calldata token) external view returns(bytes memory) {
        bytes6 _id = Helpers.tokenIdToBytes(token.id);
        bytes3 _gentag = Helpers.uintToOrdinal(token.gentag);
        bytes3 _cntrytag = Helpers.checkTagForNulls(_vFlags[token.tag]);
        bytes3 _gentush = Helpers.uintToOrdinal(token.gentush);
        bytes3 _cntrytush = _vFlags[token.tush];
        bytes1 _slash = bytes1("/");
        uint8 x = _cntrytag[2] == 0x20 ? 0 : 1;

        bytes memory _name = bytes(token.name);
        bytes memory _datap1 = '{"external_url":"https://collect9.io/nft/      ","name":"Collect9 NFT #       -         ';
        bytes memory _datap2 = ' ","description":"NFT certified ownership and possession rights for the following physical collectible: (1x qty) [                  ';
        bytes memory _datap3 = '] Beanie Baby(TM) professionally authenticated museum quality (MQ), uniquely identifiable by the authentication certificate id containing the series of numbers: XXXXXX. Redemption conditions apply. Visit the [Collect9 website](https://collect9.io) for details. Please refresh metadata to ensure status is VALID prior to offer or purchase.","image":"data:image/svg+xml;base64,';
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
     * @dev Constructs the json string containing the attributes of the token.
     * Note this continues and finishes off in `metaAttributesCloser()`.
     */
    function metaAttributes(TokenInfo calldata token) external view returns (bytes memory b) {
        bytes2[12] memory rclasses = [bytes2("T0"), "T1", "T2", "T3", "T4", "T5", "T6", "T7", "S0", "S1", "S2", "S3"];
        bytes2 _rclass = rclasses[token.rtier];
        bytes3 _gentag = Helpers.uintToOrdinal(token.gentag);
        bytes3 _cntrytag = Helpers.checkTagForNulls(_vFlags[token.tag]);
        bytes3 _gentush = Helpers.uintToOrdinal(token.gentush);
        bytes3 _cntrytush = _vFlags[token.tush];
        bytes2 _edition = Helpers.remove2Null(bytes2(Helpers.uintToBytes(token.edition)));
        bytes1 _slash = bytes1("/");
        bytes4 __mintId = Helpers.flip4Space(bytes4(Helpers.uintToBytes(token.mintid)));
        uint8 x = _cntrytag[2] == 0x20 ? 0 : 1;
        b = '","attributes":[{"trait_type":"Hang Tag Gen","value":"   "},{"trait_type":"Hang Tag Country","value":"   "},{"trait_type":"Hang Combo","value":"       "},{"trait_type":"Tush Tag Gen","value":"   "},{"trait_type":"Tush Tag Country","value":"   "},{"trait_type":"Tush Special","value":"NONE"},{"trait_type":"Tush Combo","value":"            "},{"trait_type":"Hang Tush Combo","value":"                      "},{"trait_type":"C9 Rarity Class","value":"  "},{"display_type":"number","trait_type":"Edition","value":  },{"display_type":"number","trait_type":"Edition Mint ID","value":    },{"trait_type":"Background","value":"';
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
            dst := add(b, 481)
            mstore(dst, or(and(mload(dst), not(shl(240, 0xFFFF))), _rclass))
            dst := add(b, 542)
            mstore(dst, or(and(mload(dst), not(shl(248, 0xFF))), _edition))
            dst := add(b, 610)
            mstore(dst, or(and(mload(dst), not(shl(224, 0xFFFFFFFF))), __mintId))
        }
        uint8 _markerid = token.markertush;
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
        b = bytes.concat(b, bgs[token.spec], '"}]}');
    }
}