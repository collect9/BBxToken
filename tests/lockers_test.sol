// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract LockersTest is C9TestContract {
    
    function afterEach()
    public override {
        super.afterEach();
    }

    function _adminLock(uint256 mintId, uint256 tokenId)
    private {
        c9t.adminLock(tokenId);
        _rawData[mintId].locked = LOCKED; // force raw data unlock

        bool locked = c9t.isLocked(tokenId);
        Assert.equal(locked, true, "Invalid token lock1");
        
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    function _adminUnlock(uint256 mintId, uint256 tokenId)
    private {
        c9t.adminUnlock(tokenId);
        _rawData[mintId].locked = UNLOCKED; // force raw data unlock

        bool locked = c9t.isLocked(tokenId);
        Assert.equal(locked, false, "Invalid token unlock1");
        
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    function checkTokenLockers1()
    public {
        uint256 mintId = _timestamp % (_rawData.length-4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _adminLock(mintId, tokenId);
        _adminUnlock(mintId, tokenId);
    }

    function checkTokenLockers2()
    public {
        uint256 mintId = (_timestamp + 7) % (_rawData.length-4);
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        _adminLock(mintId, tokenId);
        _adminUnlock(mintId, tokenId);
    }
}