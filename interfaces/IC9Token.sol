// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

interface IC9Token is IERC2981 {

    function getTokenParams(uint256 _tokenId) external view returns(uint256[19] memory params);

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