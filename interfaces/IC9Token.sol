// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./../utils/interfaces/IC9ERC721Base.sol";

interface IC9Token is IC9ERC721, IERC2981 {

    function baseURIArray(uint256 index)
    external view
    returns (string memory);

    function getEditionMaxMintId(uint256 edition)
    external view
    returns (uint256);

    function getInsuredsValue(uint256[] calldata tokenIds)
    external view
    returns (uint256 value);

    function getTokenParams(uint256 _tokenId) external view returns(uint256[19] memory params);

    function getTokenParamsName(uint256 tokenId)
    external view
    returns (string memory name);

    function preRedeemablePeriod()
    external view
    returns (uint256);

    function redeemAdd(uint256[] calldata _tokenIds) external;

    function redeemCancel() external;

    function redeemFinish(uint256 _redeemerData) external;

    function redeemRemove(uint256[] calldata _tokenIds) external;

    function redeemStart(uint256[] calldata _tokenIds) external;

    function preRedeemable(uint256 _tokenId) external view returns(bool);

    function setReserved(uint256[2][] calldata _data) external;

    function setTokenUpgraded(uint256 _tokenId) external;

    function setTokenValidity(uint256 _tokenId, uint256 _vId) external;

    function svgOnly() external view returns (bool);
}