// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./abstract/C9Struct.sol";
import "./interfaces/IC9Token.sol";
import "./utils/EthPricer.sol";

contract C9ValidityHandler is C9Struct, C9OwnerControl {

    // /**
    //  * @dev Handles royalties due payment, and if paid the 
    //  * token will be flagged valid again.
    //  */
    // function payRoyalties(uint256 _tokenId)
    //     external payable
    //     isOwner(_tokenId) {
    //         if (_tokens[_tokenId].validity != 1) {
    //             revert ("C9Token: token not royalties due");
    //         }
    //         uint8 _royaltiesDue = royaltiesDue[_tokenId];
    //         uint256 royaltyWeiPrice = IC9EthPriceFeed(contractPriceFeed).getTokenWeiPrice(_royaltiesDue);
    //         if (msg.value != royaltyWeiPrice) {
    //             revert("C9Token: incorrect payment amount");
    //         }
    //         (bool success,) = payable(owner).call{value: msg.value}("");
    //         if(!success) {
    //             revert("C9Token: payment failure");
    //         }
    //         _setTokenValidity(_tokenId, 0);
    // }
}