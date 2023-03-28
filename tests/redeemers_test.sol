// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RedeemersTest is C9TestContract {

    function beforeAll()
    public {
        c9t.setPreRedeemPeriod(0);
        c9t.register(0x271577b3d4a93c7c5fecc74cc37569c86d8df05e511c8acf0438f0cb98e35427);
    }

    function redeemStartMultiple()
    public {
        uint256[] memory mintIds = new uint256[](4);
        mintIds[0] = (_timestamp + 0) % (_rawData.length-4);
        mintIds[1] = (_timestamp + 1) % (_rawData.length-4);
        mintIds[2] = (_timestamp + 2) % (_rawData.length-4);
        mintIds[3] = (_timestamp + 3) % (_rawData.length-4);
        (uint256[] memory tokenIds,) = _getTokenIdsVotes(mintIds);
 
        c9t.redeemStart(tokenIds);

        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 2, "Invalid redeem start step");

        for (uint256 i; i<tokenIds.length; i++) {
            Assert.equal(tokenIds[i], rTokenIds[i], "Invalid tokenId in redeemer");
        }
    }

    function redeemCancel()
    public {
        c9t.redeemCancel();
        (uint256 step, uint256[] memory rTokenIds) = c9t.getRedeemerInfo(c9tOwner);
        Assert.equal(step, 0, "Invalid redeem start step");
        Assert.equal(rTokenIds.length, 0, "Invalid redeem start step");
    }


}