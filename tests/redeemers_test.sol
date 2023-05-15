// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17;
import "./C9BaseDeploy_test.sol";


/*
 * @dev This contract tests starting, adding, and removing tokens from the redeemer.
 * A random number of tokens are started, added, and removed each time the test 
 * is ran. Additionally, token input is shuffled prior to input to make 
 * sure input ordering does not effect output.
 */
contract RedeemersTest is C9TestContract {

    uint256 numberInRedeemer;
    uint256 constant MASK_REGISTRATION = 2**20-1;
    bytes32 constant ksig = 0x271577b3d4a93c7c5fecc74cc37569c86d8df05e511c8acf0438f0cb98e35427;
    uint256 constant code = uint256(ksig) % MASK_REGISTRATION;

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
        uint256 numberToAdd = _timestamp % 3 + 1; // Random number from 1-4 to add

        uint256[] memory mintIds = new uint256[](numberToAdd);
        for (uint256 i; i<numberToAdd; i++) {
            mintIds[i] = (_timestamp + i) % (_rawData.length-4);
            _rawData[mintIds[i]].locked = LOCKED; // Set truth
        }
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);

        _shuffle(tokenIds);
        c9t.redeemStart(c9tOwner, code, tokenIds);
        numberInRedeemer = numberToAdd;

        
        // Check basic redeemer info is correct
        uint256[] memory rTokenIds = c9t.getRedeemerTokenIds(c9tOwner);
        Assert.equal(rTokenIds.length, numberInRedeemer, "Invalid redeem tokenIds length");

        // Check all tokens are in redeemer and locked
        for (uint256 i; i<numberToAdd; i++) {
            Assert.equal(rTokenIds[i], tokenIds[i], "Invalid tokenId in redeemer");
            Assert.equal(c9t.isLocked(tokenIds[i]), true, "Invalid locked status");
            // Make sure the rest of the packed params are still ok
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }

        afterEach();
    }

    function redeemCancel()
    public {
        c9t.redeemCancel(c9tOwner);
        uint256[] memory rTokenIds = c9t.getRedeemerTokenIds(c9tOwner);
        Assert.equal(rTokenIds.length, 0, "Invalid redeem start step");

        // Not sure which ones are in redeemer anymore from mintId, so unlock all ground truth
        for (uint256 i; i<(_rawData.length-4); i++) {
            _rawData[i].locked = UNLOCKED;
        }

        afterEach();
    }

}