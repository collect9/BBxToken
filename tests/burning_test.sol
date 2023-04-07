// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract BurningTest is C9TestContract {

    // Random mintId every run
    uint256 mintId = _timestamp % (_rawData.length - 4);

    function afterEach()
    public override {
        super.afterEach();
    }

    /**
     * @dev Token must be set to a dead status before it is 
     * allowed to be burned.
     */
    function beforeAll()
    public {
        (uint256 tokenId,) = _getTokenIdVotes(mintId);

        // 1. Must be set to invalid first
        uint256 preStatus = (_timestamp % 3) + 1; // 1-3
        _grantRole(keccak256("VALIDITY_ROLE"), c9tOwner);
        _setValidityStatus(mintId, tokenId, preStatus);

        // 2. Must be set to dead before being burnable
        uint256 deadStatus = (_timestamp % 4) + 5; // 4-8
        _setValidityStatus(mintId, tokenId, deadStatus);
    }

    /* @dev 1. Checks to make sure dead status tokens cannot be redeemed.
     */ 
    function checkBurnable()
    public {
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);
        
        // 1. Update c9tOwner truth to compare against
        uint256 remainingVotes = c9t.totalVotes() - numVotes;
        balances[c9tOwner] -= 1;
        votes[c9tOwner] -= numVotes;
        tokenOwner[tokenId] = address(0);

        // 2. Burn the token
        c9t.burn(tokenId);

        // 3. Check the 'owner' is now address 0
        Assert.equal(c9t.ownerOf(tokenId), address(0), "Invalid burned address");

        // 4. Check the burned tokens array
        uint24[] memory burned = c9t.getBurned();
        Assert.equal(burned[0], tokenId, "Invalid burned tokenId");

        // 5. Check burned tokens length
        uint256 numBurned = c9t.totalBurned();
        Assert.equal(numBurned, 1, "Invalid number of burned token");

        // 6. Check total number of votes is updated properly
        Assert.equal(c9t.totalVotes(), remainingVotes, "Invalid remaining number of votes");

        // 7. Make sure total supply is still the same
        Assert.equal(c9t.totalSupply(), _rawData.length, "Invalid number of tokens");
    }

}