// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RoyaltiesTest is C9TestContract {

    uint256 constant ROYALTY_DEFAULT = 500;

    uint256 mintId;

    address royaltyReceiver;
    uint256 royaltyAmt;
    uint256 tokenId;

    function beforeAll()
    public {
        _grantRole(keccak256("VALIDITY_ROLE"), c9tOwner);
    }

    function afterEach()
    public override {
        super.afterEach();
        _checkRoyaltyInfo();
        _checkRoyaltyInfoFromParams();
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    function _checkRoyaltyInfo()
    private {
        (address receiver, uint256 royalty) = c9t.royaltyInfo(tokenId, 10000);
        Assert.equal(receiver, royaltyReceiver, "Invalid royalty receiver");
        Assert.equal(royalty, royaltyAmt, "Invalid royalty");
    }

    function _checkRoyaltyInfoFromParams()
    private {
        uint256 royalty = c9t.getOwnersParams(tokenId)[7];
        Assert.equal(royalty, royaltyAmt, "Invalid royalty2");
    }

    /* @dev 1. Royalties testing token level.
     */ 
    function checkInitRoyalties()
    public {
        mintId = _timestamp % _rawData.length;
        (tokenId,) = _getTokenIdVotes(mintId);

        // Check initial royalties are correct
        royaltyReceiver = c9tOwner;
        royaltyAmt = _rawData[mintId].royalty*10;
    }

    /* @dev 1. Royalties testing token level.
     */ 
    function checkSetRoyalties()
    public {
        royaltyReceiver = TestsAccounts.getAccount(3);
        royaltyAmt = 800;
        // Set the new royalty for the tokens
        c9t.setTokenRoyalty(tokenId, royaltyAmt, royaltyReceiver);
        // Update truth
        _rawData[mintId].royalty = royaltyAmt/10;
    }

    /* @dev 2. Royalties testing - reset at token level.
     */ 
    function checkResetTokenRoyalties()
    public {
        mintId = _timestamp % _rawData.length;
        (tokenId,) = _getTokenIdVotes(mintId);
        royaltyReceiver = c9tOwner;
        royaltyAmt = ROYALTY_DEFAULT;
        c9t.resetTokenRoyalty(tokenId);
        // Update truth
        _rawData[mintId].royalty = royaltyAmt/10;
    }

    /* @dev 3. Royalties due testing.
     */ 
    function checkSetRoyaltiesDue()
    public {
        mintId = _timestamp % _rawData.length;
        (tokenId,) = _getTokenIdVotes(mintId);
        uint256 royaltiesDue = _timestamp % U_MASK_ROYALTIES_DUE;
        
        _setValidityStatus(mintId, tokenId, ROYALTIES);
        c9t.setRoyaltiesDue(tokenId, royaltiesDue);

        // Make sure royalties due is correct
        Assert.equal(c9t.getTokenParams(tokenId)[10], royaltiesDue, "Invalid royalties due");

        // Update truth
        _rawData[mintId].royaltiesdue = royaltiesDue;
    }
}
    