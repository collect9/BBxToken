// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RedeemablesTest is C9TestContract {

    function _checkPreRedeemable(uint256 tokenId)
    private {
        _checkRedeemable(tokenId, 0, true);
    }

    function _checkRedeemable(uint256 tokenId, uint256 status, bool isRedeemable)
    private {
        // Initial status after contract deployment
        Assert.equal(c9t.preRedeemable(tokenId), true, "Invalid false pre-redeemable 1 status");
        Assert.equal(c9t.isRedeemable(tokenId), false, "Invalid false isRedeemable 1 status");

        // Set pre-redeem period to zero so tokens become redeemable
        c9t.setPreRedeemPeriod(0);
        
        // Set and make sure validity status is correct
        if (status > 0) {
            _setValidityStatus(tokenId, status);
        }

        // Check new redemption conditions of the token
        Assert.equal(c9t.preRedeemable(tokenId), false, "Invalid false pre-redeemable 2 status");
        Assert.equal(c9t.isRedeemable(tokenId), isRedeemable, "Invalid true isRedeemable 2 status");

        c9t.setPreRedeemPeriod(86400);

        // If token status was not changed, check to see we've returned to initial condition
        if (status == 0) {
            Assert.equal(c9t.preRedeemable(tokenId), true, "Invalid false pre-redeemable 3 status");
            Assert.equal(c9t.isRedeemable(tokenId), false, "Invalid false isRedeemable 3 status");
        }
    }

    function _setValidityStatus(uint256 tokenId, uint256 status)
    private {
        c9t.setTokenValidity(tokenId, status);
        uint256 validityStatus = c9t.getTokenParams(tokenId)[2];
        Assert.equal(validityStatus, status, "Invalid validity status");
    }

    /* @dev 1. Checks if preredeemable is working properly
     * for existing valid tokens.
     */ 
    function _checkValidRedeemable()
    public {
        // Test preRedeemPeriod
        uint256 mintId = _timestamp % (_rawData.length - 4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _checkPreRedeemable(tokenId);
    }

    /* @dev 2. Checks to make sure dead status tokens cannot be redeemed.
     */ 
    function checkDeadRedeemable()
    public {
        // Last token is already a dead status, so it should not be redeemable
        (uint256 tokenId,) = _getTokenIdVotes(_rawData.length-1);
        _checkRedeemable(tokenId, 0, false);

        // Set a valid token be to dead and make sure it is not redeemable
        uint256 mintId = _timestamp % (_rawData.length - 4);
        (tokenId,) = _getTokenIdVotes(mintId);
        _checkPreRedeemable(tokenId);

        // Cannot change from valid to dead, so must change to invalid (1-3) first
        uint256 preStatus = (_timestamp % 3) + 1; // 1-3
        uint256 deadStatus = (_timestamp % 4) + 5; // 4-8
        _setValidityStatus(tokenId, preStatus);
        _checkRedeemable(tokenId, deadStatus, false);
    }

    /* @dev 3. Checks to make sure inactive status is still redeemable.
     */ 
    function checkInactiveRedeemable()
    public {
        uint256 mintId = (_timestamp + 1) % (_rawData.length - 4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _checkRedeemable(tokenId, INACTIVE, true);
    }

    /* @dev 3. Checks to make sure other status is NOT redeemable.
     */ 
    function checkOtherRedeemable()
    public {
        uint256 mintId = (_timestamp + 2) % (_rawData.length - 4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _checkRedeemable(tokenId, OTHER, false);
    }

    /* @dev 4. Checks to make sure validity royalties is NOT redeemable.
     */ 
    function checkRoyaltiesRedeemable()
    public {
        uint256 mintId = (_timestamp + 3) % (_rawData.length - 4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _checkRedeemable(tokenId, ROYALTIES, false);
    }
}
    