// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract SettersTest is C9TestContract {

    /* @dev 1. Tests token set upgrade and set display.
     */ 
    function checkSetTokenUpgradedDisplay()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        
        c9t.setTokenUpgraded(tokenId);
        uint256 upgradedSet = c9t.getTokenParams(tokenId)[3];
        Assert.equal(upgradedSet, 1, "Invalid upgraded value");

        c9t.setTokenDisplay(tokenId, true);
        uint256 displaySet = c9t.getTokenParams(tokenId)[4];
        Assert.equal(displaySet, 1, "Invalid display1 set");

        c9t.setTokenDisplay(tokenId, false);
        displaySet = c9t.getTokenParams(tokenId)[4];
        Assert.equal(displaySet, 0, "Invalid display set");
    }

    /* @dev 2. Tests string setters.
     */
    function checkSetters()
    public {
        // Base URI testing
        string memory baseURI0 = "testbaseuri/uri0/";
        string memory baseURI1 = "testbaseuri/uri1/"; 
        c9t.setBaseUri(baseURI0, 0);
        c9t.setBaseUri(baseURI1, 1);
        Assert.equal(baseURI0, c9t.baseURIArray(0), "Invalid baseURI0");
        Assert.equal(baseURI1, c9t.baseURIArray(1), "Invalid baseURI1");

        // Contract URI testing
        string memory contractURI = "somecontract/uri";
        c9t.setContractURI(contractURI);
        Assert.equal(string.concat("https://", contractURI, ".json"), c9t.contractURI(), "Invalid contractURI");
    }
}
    