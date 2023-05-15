// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract SettersTest is C9TestContract {

    function afterEach()
    public override {
        super.afterEach();
    }

    /* @dev 1. Check contract setters.
     */ 
    function checkSetContracts()
    public {
        address contract1 = TestsAccounts.getAccount(1);
        address contract2 = TestsAccounts.getAccount(2);

        c9t.setContractMeta(contract1);
        c9t.setContractPricer(contract2);

        (address contractMeta, address contractPricer) = c9t.getContracts();

        // Check contracts
        Assert.equal(contractMeta, contract1, "Invalid meta contract");
        Assert.equal(contractPricer, contract2, "Invalid pricer contract");
    }

    /* @dev 3. Tests string setters.
     */
    function checkStringSetters()
    public {
        // Base URI testing
        string memory baseURI0 = "testbaseuri/uri0/";
        string memory baseURI1 = "testbaseuri/uri1/"; 
        c9t.setBaseURI(baseURI0, 0);
        c9t.setBaseURI(baseURI1, 1);
        Assert.equal(baseURI0, c9t.baseURIArray(0), "Invalid baseURI0");
        Assert.equal(baseURI1, c9t.baseURIArray(1), "Invalid baseURI1");

        // Contract URI testing
        string memory contractURI = "somecontract/uri";
        c9t.setContractURI(contractURI);
        Assert.equal(string.concat("https://", contractURI, ".json"), c9t.contractURI(), "Invalid contractURI");
    }
}
    