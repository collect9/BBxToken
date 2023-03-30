// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


/*
 * @dev This contract tests starting, adding, and removing tokens from the redeemer.
 * A random number of tokens are started, added, and removed each time the test 
 * is ran. Additionally, token input is shuffled prior to input to make 
 * sure input ordering does not effect output.
 */
contract RedeemersTest is C9TestContract {

    uint256 numberInRedeemer;

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
        c9t.register(0x271577b3d4a93c7c5fecc74cc37569c86d8df05e511c8acf0438f0cb98e35427);
        regStatus = true; //Set truth
        _checkOwnerDataOf(c9tOwner);
    }

    function redeemStartMultiple()
    public {
        uint256 numberToAdd = _timestamp % 3 + 1; // Random number from 1-4 to add

        uint256[] memory mintIds = new uint256[](numberToAdd);
        for (uint256 i; i<numberToAdd; i++) {
            mintIds[i] = (_timestamp + i) % (_rawData.length-4);
            _rawData[mintIds[i]].locked = LOCKED; // Set truth
        }
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);

        _shuffle(tokenIds);
        c9t.redeemStart(tokenIds);
        numberInRedeemer = numberToAdd;

        // Check basic redeemer info is correct
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem start step");
        Assert.equal(rTokenIds.length, numberInRedeemer, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<numberToAdd; i++) {
            Assert.equal(rTokenIds[i], tokenIds[i], "Invalid tokenId in redeemer");
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
            // Make sure the rest of the packed params are still ok
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }
    }

    function redeemAddMultiple()
    public {
        uint256 numberToAddAtMost = 6 - numberInRedeemer;
        uint256 numberToAdd = _timestamp % numberToAddAtMost + 1; // Random number from 1-X to add

        uint256[] memory mintIds = new uint256[](numberToAdd);
        for (uint256 i; i<numberToAdd; i++) {
            mintIds[i] = (_timestamp + i + numberInRedeemer) % (_rawData.length-4);
            _rawData[mintIds[i]].locked = LOCKED; // Set truth
        }
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);
        
        _shuffle(tokenIds);
        c9t.redeemAdd(tokenIds);
        
        // Check basic redeemer info is correct
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem add step");
        Assert.equal(rTokenIds.length, numberInRedeemer+numberToAdd, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<numberToAdd; i++) {
            Assert.equal(rTokenIds[i+numberInRedeemer], tokenIds[i], "Invalid tokenId added to redeemer");
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
            // Make sure the rest of the packed params are still ok
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }
        // Update truth
        numberInRedeemer += numberToAdd;
    }

    function redeemRemoveMultiple()
    public {
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem add step");
        Assert.equal(rTokenIds.length, numberInRedeemer, "Invalid redeem tokenIds length");

        // TokenIds to remove
        uint256 numberToRemove = _timestamp % (numberInRedeemer-1) + 1; // Random amount from 1-X to remove
        Assert.equal(numberToRemove>0, true, "Invalid number to remove");
        uint256[] memory removeTokenIds = new uint256[](numberToRemove);
        for (uint256 i; i<numberToRemove; i++) {
            removeTokenIds[i] = rTokenIds[(_timestamp + i) % numberInRedeemer];
        }

        // TokenIds that will remain
        uint256 numberToRemain = numberInRedeemer - numberToRemove; // Random number from 1-X that will remain
        Assert.equal(numberToRemain>0, true, "Invalid number to remain");
        Assert.equal(numberToRemain+numberToRemove, numberInRedeemer, "Invalid remove remain combo");
        uint256[] memory remainingTokenIds = new uint256[](numberToRemain);
        for (uint256 i; i<numberToRemain; i++) {
            remainingTokenIds[i] = rTokenIds[(_timestamp + i + numberToRemove) % numberInRedeemer];
        }

        // Remove tokenIds and check basic info
        _shuffle(removeTokenIds);
        c9t.redeemRemove(removeTokenIds);
        (uint256 step2, uint256[] memory lTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step2, 2, "Invalid redeem add step");
        Assert.equal(lTokenIds.length, numberToRemain, "Invalid redeem tokenIds length");

        // Make sure removed ones are unlocked
        for (uint256 i; i<numberToRemove; i++) {
            Assert.equal(c9t.isLocked(removeTokenIds[i]), false, "Invalid unlocked status");
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

    function redeemCancel()
    public {
        c9t.redeemCancel();
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 0, "Invalid redeem start step");
        Assert.equal(rTokenIds.length, 0, "Invalid redeem start step");
    }


}