// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract UpgradersTest is C9TestContract {

    uint256 mintId;
    uint256 tokenId;

    function beforeAll()
    public {
        _grantRole(keccak256("UPGRADER_ROLE"), c9tOwner);
        mintId = _timestamp % _rawData.length;
        (tokenId,) = _getTokenIdVotes(mintId);
    }

    function afterEach()
    public override {
        super.afterEach();
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    /* @dev 1. Tests token set upgrade and set display.
     */ 
    function checkSetTokenUpgraded()
    public {
        c9t.setTokenUpgraded(tokenId);
        _rawData[mintId].upgraded = 1; // Set truth
        uint256 upgradedSet = c9t.getOwnersParams(tokenId)[3];
        Assert.equal(upgradedSet, 1, "Invalid upgraded value");
    }

    function checkSetTokenDisplayTrue()
    public {
        c9t.setTokenDisplay(tokenId, true);
        _rawData[mintId].display = 1; // Set truth
        uint256 displaySet = c9t.getOwnersParams(tokenId)[4];
        Assert.equal(displaySet, 1, "Invalid display1 set");
    }

    function checkSetTokenDisplayFalse()
    public {
        c9t.setTokenDisplay(tokenId, false);
        _rawData[mintId].display = 0; // Set truth
        uint256 displaySet = c9t.getOwnersParams(tokenId)[4];
        Assert.equal(displaySet, 0, "Invalid display set");
    }
}