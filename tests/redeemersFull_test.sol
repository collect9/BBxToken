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

    uint256 constant NUMBER_TO_REDEEM = 3;
    uint256 constant NUMBER_TO_ADD_REMOVE = 2;
    uint256[NUMBER_TO_REDEEM] mintIds;
    uint256[NUMBER_TO_REDEEM] tokenIds;

    function afterEach()
    public override {
        super.afterEach();
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }
    }

    // Redeemer open requirements
    // 1. No redeem period blocking
    // 2. Account trying to redeem is registered
    function beforeAll()
    public {
        c9t.setPreRedeemPeriod(0);
        c9t.register(0x271577b3d4a93c7c5fecc74cc37569c86d8df05e511c8acf0438f0cb98e35427);
        regStatus = true; //Set truth
        _checkOwnerDataOf(c9tOwner);
    }

    function redeemStartMultiple()
    public {
        uint256[] memory _mintIds = new uint256[](NUMBER_TO_REDEEM);
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            _mintIds[i] = (_timestamp + i) % (_rawData.length-4);
            _rawData[_mintIds[i]].locked = LOCKED; // Set truth
        }
        (uint256[] memory _tokenIds,) = _getTokenIdsVotes(_mintIds);

        //_shuffle(_tokenIds);
        c9t.redeemStart(_tokenIds);

        // Check basic redeemer info is correct
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem start step");
        Assert.equal(rTokenIds.length, NUMBER_TO_REDEEM, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            // Copy to storage for later
            tokenIds[i] = _tokenIds[i];
            mintIds[i] = _mintIds[i];

            Assert.equal(rTokenIds[i], tokenIds[i], "Invalid tokenId in redeemer");
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
        }
    }

    function redeemRemoveMultiple()
    public {
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem add step");
        Assert.equal(rTokenIds.length, NUMBER_TO_REDEEM, "Invalid redeem tokenIds length");

        // TokenIds to remove (remove last two)
        uint256[] memory removeTokenIds = new uint256[](NUMBER_TO_ADD_REMOVE);
        for (uint256 i; i<NUMBER_TO_ADD_REMOVE; i++) {
            removeTokenIds[i] = rTokenIds[i+1];
        }

        // TokenIds that will remain
        uint256 numberToRemain = NUMBER_TO_REDEEM - NUMBER_TO_ADD_REMOVE; // Random number from 1-X that will remain
        Assert.equal(numberToRemain>0, true, "Invalid number to remain");
        Assert.equal(numberToRemain+NUMBER_TO_ADD_REMOVE, NUMBER_TO_REDEEM, "Invalid remove remain combo");
        uint256[] memory remainingTokenIds = new uint256[](numberToRemain);
        remainingTokenIds[0] = rTokenIds[0]; // Keep the first token

        // Remove tokenIds and check basic info
        c9t.redeemRemove(removeTokenIds);
        (uint256 step2, uint256[] memory lTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step2, 2, "Invalid redeem add step");
        Assert.equal(lTokenIds.length, numberToRemain, "Invalid redeem tokenIds length");

        // Make sure removed ones are unlocked
        for (uint256 i; i<NUMBER_TO_ADD_REMOVE; i++) {
            Assert.equal(c9t.isLocked(removeTokenIds[i]), false, "Invalid unlocked status");
            _rawData[mintIds[i+1]].locked = UNLOCKED; // Set truth for afterEach
        }

        // Check the ones remaining in the redeemer are correct
        uint256 correctCounter;
        for (uint256 i; i<numberToRemain; i++) {
            for (uint256 j; j<numberToRemain; j++) {
                if (lTokenIds[j] == remainingTokenIds[i]) {
                    ++correctCounter;
                }
            }
        }
        Assert.equal(correctCounter, numberToRemain, "Invalid correctness counter");
    }

    function redeemAddMultiple()
    public {
        uint256[] memory _mintIds = new uint256[](NUMBER_TO_ADD_REMOVE);
        for (uint256 i; i<NUMBER_TO_ADD_REMOVE; i++) {
            _mintIds[i] = (_timestamp + NUMBER_TO_REDEEM + i) % (_rawData.length-4);
        }
        (uint256[] memory _tokenIds,) = _getTokenIdsVotes(_mintIds);
        
        c9t.redeemAdd(_tokenIds);
        
        // Check basic redeemer info is correct
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem add step");
        Assert.equal(rTokenIds.length, NUMBER_TO_REDEEM, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<NUMBER_TO_ADD_REMOVE; i++) {
            Assert.equal(rTokenIds[i+1], _tokenIds[i], "Invalid tokenId added to redeemer");
            Assert.equal(c9t.isLocked(_tokenIds[i]), true, "Invalid locked status");
            
            // Copy to storage for later
            mintIds[i+1] = _mintIds[i];
            tokenIds[i+1] = _tokenIds[i];

            _rawData[mintIds[i+1]].locked = LOCKED; // Set truth for afterEach
        }
    }

    function verifyRedemption()
    public {
        uint256 code = 719959;
        c9t.userVerifyRedemption(code); // Zero payment for testing

        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 3, "Invalid redeem  add step");
        Assert.equal(rTokenIds.length, NUMBER_TO_REDEEM, "Invalid redeem tokenIds length");

        // Check the ones remaining in the redeemer are correct
        uint256 correctCounter;
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            for (uint256 j; j<NUMBER_TO_REDEEM; j++) {
                if (tokenIds[i] == rTokenIds[j]) {
                    ++correctCounter;
                }
            }
        }
         Assert.equal(correctCounter, NUMBER_TO_REDEEM, "Invalid correctness counter");
    }

    function adminFinalizeRedemption()
    public {
        uint256 ts = block.timestamp;
        c9t.adminFinalApproval(c9tOwner);

        // After approval the redeemer should be back at step 0
        (uint256 step,) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 0, "Invalid redeem  add step");

        // Check all tokens have still been locked and are redeemed status
        for (uint256 i; i<NUMBER_TO_REDEEM; i++) {
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
            Assert.equal(c9t.validityStatus(tokenIds[i]), REDEEMED, "Invalid validity status");
            Assert.equal(c9t.getRedeemed()[i], tokenIds[i], "Invalid redeemed tokenId");

            // Set ground truth
            _rawData[mintIds[i]].validity = REDEEMED;
            _rawData[mintIds[i]].validitystamp = ts;
        }

        // // Update truthing
        redemptions[c9tOwner] += NUMBER_TO_REDEEM;
        redeemCounter += NUMBER_TO_REDEEM;

        Assert.equal(c9t.totalRedeemed(), redeemCounter, "Invalid locked status");
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