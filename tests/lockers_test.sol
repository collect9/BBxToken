// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract LockersTest is C9TestContract {
    
    function afterEach()
    public override {
        super.afterEach();
    }

    function _adminLock(uint256 mintId, uint256 tokenId)
    private {
        //c9t.adminLock(tokenId);
        _rawData[mintId].locked = LOCKED; // force raw data unlock

        bool locked = c9t.isLocked(tokenId);
        Assert.equal(locked, true, "Invalid token lock1");
        
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    function _adminUnlock(uint256[] memory mintIds, uint256[] memory tokenIds)
    private {

        c9t.adminUnlock(tokenIds);
        

        for (uint256 i; i<tokenIds.length; i++) {
            _rawData[mintIds[i]].locked = UNLOCKED; // force raw data unlock
            bool locked = c9t.isLocked(tokenIds[i]);
            Assert.equal(locked, false, "Invalid token unlock1");        
            _checkTokenParams(mintIds[i]);
            _checkOwnerParams(mintIds[i]);
        }
    }

    function checkTokenLockers1()
    public {
        uint256[] memory mintIds = new uint256[](2);
        // These tokens are default locked
        for (uint256 i; i<2; i++) {
            mintIds[i] = (DATA_SIZE-4) + i;
        }
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);

        //_adminLock(mintId, tokenId);
        _adminUnlock(mintIds, tokenIds);
    }
}