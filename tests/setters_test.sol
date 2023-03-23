// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract SettersTest is C9TestContract {

    /* @dev 1. Check contract setters.
     */ 
    function checkSetContracts()
    public {
        address contract1 = TestsAccounts.getAccount(1);
        address contract2 = TestsAccounts.getAccount(2);
        address contract4 = TestsAccounts.getAccount(4);
        address contract5 = TestsAccounts.getAccount(5);

        c9t.setContractMeta(contract1);
        c9t.setContractRedeemer(contract2);
        c9t.setContractUpgrader(contract4);
        c9t.setContractVH(contract5);

        (address contractMeta, address contractRedeemer, address contractUpgrader, address contractVH) = c9t.getContracts();

        // Check contracts
        Assert.equal(contractMeta, contract1, "Invalid meta contract");
        Assert.equal(contractRedeemer, contract2, "Invalid redeemer contract");
        Assert.equal(contractUpgrader, contract4, "Invalid upgrader contract");
        Assert.equal(contractVH, contract5, "Invalid vh contract");

        // Check roles
        Assert.equal(c9t.hasRole(c9t.REDEEMER_ROLE(), contractRedeemer), true, "redeemer role not set");
        Assert.equal(c9t.hasRole(c9t.UPGRADER_ROLE(), contractUpgrader), true, "upgrader role not set");
        Assert.equal(c9t.hasRole(c9t.VALIDITY_ROLE(), contractVH), true, "validity role not set");

    }

    /* @dev 2. Tests token set upgrade and set display.
     */ 
    function checkSetTokenUpgradedDisplay()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        
        c9t.setTokenUpgraded(tokenId);
        uint256 upgradedSet = c9t.getOwnersParams(tokenId)[3];
        Assert.equal(upgradedSet, 1, "Invalid upgraded value");

        c9t.setTokenDisplay(tokenId, true);
        uint256 displaySet = c9t.getOwnersParams(tokenId)[4];
        Assert.equal(displaySet, 1, "Invalid display1 set");

        c9t.setTokenDisplay(tokenId, false);
        displaySet = c9t.getOwnersParams(tokenId)[4];
        Assert.equal(displaySet, 0, "Invalid display set");
    }

    /* @dev 3. Tests string setters.
     */
    function checkStringSetters()
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

    /* @dev 4. Tests for account reserved space setters.
     */
    function checkAccountReserved()
    public {
        // Must enable reserved space
        c9t.toggleReservedBalanceSpace(true);

        c9t.setReservedBalanceSpace(_timestamp);
        uint256 reservedResult = c9t.getReservedBalanceSpace(c9tOwner);
        Assert.equal(reservedResult, _timestamp, "Invalid account reserved 1");

        uint256 randomness = uint256(uint104(uint256(keccak256(abi.encodePacked(_timestamp)))));
        c9t.setReservedBalanceSpace(randomness);
        reservedResult = c9t.getReservedBalanceSpace(c9tOwner);
        Assert.equal(reservedResult, randomness, "Invalid account reserved 2");

        c9t.setReservedBalanceSpace(_timestamp);
        reservedResult = c9t.getReservedBalanceSpace(c9tOwner);
        Assert.equal(reservedResult, _timestamp, "Invalid account reserved 3");
    }
}
    