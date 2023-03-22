// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract LockersTest is C9TestContract {
    
    function _adminUnlock(uint256 tokenId)
    private {
        c9t.adminUnlock(tokenId);
        bool locked = c9t.isLocked(tokenId);
        Assert.equal(locked, false, "Invalid token unlock1");
        uint256 iLocked = c9t.getOwnersParams(tokenId)[5];
        Assert.equal(iLocked, UNLOCKED, "Invalid token unlock2");
    }

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

    function checkTokenUnlockers()
    public {
        uint256 mintId = 28;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        Assert.equal(_rawData[mintId].locked, LOCKED, "Invalid token lock1");
        _adminUnlock(tokenId);

        mintId = 29;
        (tokenId,) = _getTokenIdVotes(mintId);
        Assert.equal(_rawData[mintId].locked, LOCKED, "Invalid token lock2");
        _adminUnlock(tokenId);
    }


}
    