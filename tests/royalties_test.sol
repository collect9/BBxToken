// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RoyaltiesTest is C9TestContract {

    function _checkRoyaltyInfo(uint256 tokenId, uint256 royaltyAmt, address royaltyReceiver)
    private {
        (address receiver, uint256 royalty) = c9t.royaltyInfo(tokenId, 10000);
        Assert.equal(receiver, royaltyReceiver, "Invalid royalty receiver");
        Assert.equal(royalty, royaltyAmt, "Invalid royalty");
    }

    /* @dev 1. Royalties testing - global.
     */ 
    function checkSetGlobalRoyalties()
    public {
        // Check to make sure info is read correctly
        _checkRoyaltyInfo(0, 500, c9tOwner);
    }

    /* @dev 2. Royalties testing - token level.
     */ 
    function checkSetTokenRoyalties()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        address newReceiver = TestsAccounts.getAccount(3);
        uint256 newRoyaltyAmt = 800;

        // Set the new royalty for the tokens
        c9t.setTokenRoyalty(tokenId, newRoyaltyAmt, newReceiver);

        // Check to make sure updated info is read correctly
        _checkRoyaltyInfo(tokenId, newRoyaltyAmt, newReceiver);
    }

    /* @dev 3. Royalties testing - reset at token level.
     */ 
    function checkResetTokenRoyalties()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        c9t.resetTokenRoyalty(tokenId);
        _checkRoyaltyInfo(tokenId, 500, c9tOwner);
    }

    /* @dev 4. Royalties due testing.
     */ 
    function checkSetRoyaltiesDue()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        uint256 royaltiesDue = 8791;
        
        c9t.setTokenValidity(tokenId, ROYALTIES);
        c9t.setRoyaltiesDue(tokenId, royaltiesDue);
        uint256 royaltiesDueSet = c9t.getTokenParams(tokenId)[20];
        Assert.equal(royaltiesDueSet, royaltiesDue, "Invalid royalties due");
    }
}
    