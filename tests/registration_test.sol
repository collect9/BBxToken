// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RegistrationTest is C9TestContract {

    bytes32 ksig;

    function afterEach()
    public override {
        // Check c9towner params
        super.afterEach();
    }

    function _checkRegistration(bool alreadyRegistered)
    private {
        // Should be bool alreadyRegistered to start
        bool isRegistered = c9t.isRegistered(c9tOwner);
        Assert.equal(isRegistered, alreadyRegistered, "registration error1");

        // Regisater with ksig random registration data
        c9t.register(ksig);
        regStatus = true; // ground truth update

        // Check isRegistered
        isRegistered = c9t.isRegistered(c9tOwner);
        Assert.equal(isRegistered, true, "registration error2");
    }

    function checkPreRegistration()
    public {
        ksig = keccak256(abi.encodePacked(block.timestamp));
        _checkRegistration(false);
    }

    function checkReRegistration()
    public {
        ksig = keccak256(abi.encodePacked("some random data"));
        _checkRegistration(true);
    }



}