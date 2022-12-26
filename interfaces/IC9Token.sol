// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

error AddressAlreadySet(); //0xf62c2d82
error CallerNotContract(); //0xa85366a7
error EditionOverflow(uint256 received); //0x5723b5d1
error IncorrectTokenValidity(uint256 expected, uint256 received); //0xe8c07318
error InvalidVId(uint256 received); //0xcf8cffb0
error NoOwnerSupply(address sender); //0x973d81af
error PeriodTooLong(uint256 maxPeriod, uint256 received); //0xd36b55de
error RoyaltiesAlreadySet(); //0xe258016d
error RoyaltyTooHigh(); //0xc2b03beb
error ValueAlreadySet(); //0x30a4fcdc
error URIAlreadySet(); //0x82ccdaca
error URIMissingEndSlash(); //0x21edfe88
error TokenAlreadyUpgraded(uint256 tokenId); //0xb4aab4a3
error TokenIsDead(uint256 tokenId); //0xf87e5785
error TokenIsLocked(uint256 tokenId); //0xdc8fb341
error TokenNotLocked(uint256 tokenId); //0x5ef77436
error TokenNotUpgraded(uint256 tokenId); //0x14388074
error TokenPreRedeemable(uint256 tokenId); //0x04df46e6
error Unauthorized(); //0x82b42900
error ZeroEdition(); //0x2c0dcd39
error ZeroMintId(); //0x1ed046c6
error ZeroValue(); //0x7c946ed7
error ZeroTokenId(); //0x1fed7fc5

interface IC9Token {

    function getTokenParams(uint256 _tokenId) external view returns(uint256[18] memory params);

    function ownerOf(uint256 _tokenId) external view returns(address);

    function redeemAdd(uint256[] calldata _tokenIds) external;

    function redeemCancel() external;

    function redeemFinish(uint256 _redeemerData) external;

    function redeemRemove(uint256[] calldata _tokenIds) external;

    function redeemStart(uint256[] calldata _tokenIds) external;

    function preRedeemable(uint256 _tokenId) external view returns(bool);

    function setTokenUpgraded(uint256 _tokenId) external;

    function setTokenValidity(uint256 _tokenId, uint256 _vId) external;
}