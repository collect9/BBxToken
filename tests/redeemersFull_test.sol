// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


/*
 * @dev This contract tests starting, adding, and removing tokens from the redeemer.
 * A random number of tokens are started, added, and removed each time the test 
 * is ran. Additionally, token input is shuffled prior to input to make 
 * sure input ordering does not effect output.
 */
contract RedeemersTestFull is C9TestContract {

    uint256 immutable NUMBER_TO_REDEEM = _timestamp % 5 + 1;
    uint256[] mintIds;

    uint256 constant MASK_REGISTRATION = 2**20-1;
    bytes32 constant ksig = 0x271577b3d4a93c7c5fecc74cc37569c86d8df05e511c8acf0438f0cb98e35427;
    uint256 constant code = uint256(ksig) % MASK_REGISTRATION;

    function afterEach()
    public override {
        super.afterEach();
    }

    function _shuffle(uint256[] memory numberArr)
    private view {
        for (uint256 i; i<numberArr.length; i++) {
            uint256 n = i + uint256(keccak256(abi.encodePacked(_timestamp))) % (numberArr.length - i);
            uint256 temp = numberArr[n];
            numberArr[n] = numberArr[i];
            numberArr[i] = temp;
        }
    }

    // Redeemer open requirements
    // 1. No redeem period blocking
    // 2. Account trying to redeem is registered
    function beforeAll()
    public {
        c9t.setPreRedeemPeriod(0);
        c9t.register(ksig);
        c9t.setBaseFees(0); // 0 fees makes redeemer not payable
        regStatus = true; //Set truth
        _checkOwnerDataOf(c9tOwner);
    }

    function redeemStart()
    public {
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            mintIds.push( (_timestamp + i) % (_rawData.length-4) );
            _rawData[mintIds[i]].locked = LOCKED; // Set truth
        }
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);

        _shuffle(tokenIds);
        c9t.redeemStart(c9tOwner, code, tokenIds);

        // Check basic redeemer info is correct
        uint256[] memory rTokenIds = c9t.getRedeemerTokenIds(c9tOwner);
        Assert.equal(rTokenIds.length, NUMBER_TO_REDEEM, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            Assert.equal(rTokenIds[i], tokenIds[i], "Invalid tokenId in redeemer");
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
            // Make sure the rest of the packed params are still ok
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }

        afterEach();
    }

    function adminFinalizeRedemption()
    public {
        uint256[] memory rTokenIds = c9t.getRedeemerTokenIds(c9tOwner);

        uint256 ts = block.timestamp;
        c9t.adminFinalApprove(c9tOwner);

        
        // After approval the redeemer should be back at step 0
        uint256[] memory doneTokenIds = c9t.getRedeemerTokenIds(c9tOwner);
        Assert.equal(doneTokenIds.length, 0, "Invalid redeem tokenIds length after approved");

        // Check all tokens have still been locked and are redeemed status
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            Assert.equal(c9t.isLocked(rTokenIds[i]), true, "Invalid locked status");
            Assert.equal(c9t.validityStatus(rTokenIds[i]), REDEEMED, "Invalid validity status");
            Assert.equal(c9t.getRedeemed()[i], rTokenIds[i], "Invalid redeemed tokenId");

            // Set ground truth
            _rawData[mintIds[i]].validity = REDEEMED;
            _rawData[mintIds[i]].validitystamp = ts;
        }

        // Update truthing
        redemptions[c9tOwner] += NUMBER_TO_REDEEM;
        redeemCounter += NUMBER_TO_REDEEM;

        Assert.equal(c9t.totalRedeemed(), redeemCounter, "Invalid total redeemed");
    }
    
    
    function burnRedeemed()
    public {
        uint256[] memory _mintIds = new uint256[](NUMBER_TO_REDEEM);
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            _mintIds[i] = mintIds[i];
        }
        (uint256[] memory _tokenIds, uint256 numVotes) = _getTokenIdsVotes(_mintIds);

        uint256 remainingVotes = c9t.totalVotes() - numVotes;
        balances[c9tOwner] -= NUMBER_TO_REDEEM;
        votes[c9tOwner] -= numVotes;

        // 2. Burn the token and set truth
        uint256 tokenId;
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            tokenId = _tokenIds[i];
            tokenOwner[tokenId] = address(0);
            c9t.burn(tokenId);

            // 3. Check the 'owner' is now address 0
            Assert.equal(c9t.ownerOf(tokenId), address(0), "Invalid burned address");

            // 4. Check the burned tokens array
            uint24[] memory burned = c9t.getBurned();
            Assert.equal(burned[i], tokenId, "Invalid burned tokenId");
        }

        // 5. Check burned tokens length
        uint256 numBurned = c9t.totalBurned();
        Assert.equal(numBurned, NUMBER_TO_REDEEM, "Invalid number of burned token");

        // 6. Check total number of votes is updated properly
        Assert.equal(c9t.totalVotes(), remainingVotes, "Invalid remaining number of votes");

        // 7. Make sure total supply is still the same
        Assert.equal(c9t.totalSupply(), _rawData.length, "Invalid number of tokens");
    }
}