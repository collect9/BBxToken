// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract LockersTest is C9TestContract {
    /* @dev 1. Check account lockers.
     */
    function checkAccountLockers()
    public {
        c9t.userLockAddress(86400);
        
        // Check the account locked and lockStamp is correct
        (bool locked, uint256 lockStamp) = c9t.ownerLocked(c9tOwner);
        Assert.equal(locked, true, "Invalid account lock");
        Assert.equal(lockStamp, block.timestamp, "Invalid account lock timestamp");

        // // Check the user can unlock
        // c9t.userUnlockAddress();
        // (locked, lockStamp) = c9t.ownerLocked(c9tOwner);
        // Assert.equal(locked, false, "Invalid account lock");
        // Assert.equal(lockStamp, block.timestamp, "Invalid account lock timestamp");
    }


}
    