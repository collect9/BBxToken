// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract BurningTest is C9TestContract {

    /* @dev 1. Checks to make sure dead status tokens cannot be redeemed.
     */ 
    function checkBurnable()
    public {
        // Set a valid token be to dead and make sure it is burnable
        uint256 mintId = _timestamp % (_rawData.length - 4);
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);
        // Must be invalid before dead
        uint256 preStatus = (_timestamp % 3) + 1; // 1-3
        _setValidityStatus(tokenId, preStatus);
        uint256 deadStatus = (_timestamp % 4) + 5; // 4-8
        _setValidityStatus(tokenId, deadStatus);

        // First get the new number of votes that will remain
        uint256 remainingVotes = c9t.totalVotes() - numVotes;

        // Burn the token
        c9t.burn(tokenId);

        // Check the 'owner' is now address 0
        Assert.equal(c9t.ownerOf(tokenId), address(0), "Invalid burned address");

        // Check the burned tokens array
        uint24[] memory burned = c9t.getBurned();
        Assert.equal(burned[0], tokenId, "Invalid burned tokenId");

        // Check burned tokens length
        uint256 numBurned = c9t.totalBurned();
        Assert.equal(numBurned, 1, "Invalid number of burned token");

        // Check total number of votes is updated properly
        Assert.equal(remainingVotes, c9t.totalVotes(), "Invalid remaining number of votes");

        // Make sure total supply is still the same
        uint256 totalSupply = c9t.totalSupply();
        Assert.equal(totalSupply, _rawData.length, "Invalid number of tokens");
    }

}