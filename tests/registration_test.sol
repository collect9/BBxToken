// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract RegistrationTest is C9TestContract {

    function _checkRegistration(bytes32 ksig, bool alreadyRegistered)
    private {
        // Should not be registered to start
        bool isRegistered = c9t.isRegistered(c9tOwner);
        Assert.equal(isRegistered, alreadyRegistered, "pre-registration error");

        // Random registration data
        c9t.register(ksig);

        // Check if now registered
        isRegistered = c9t.isRegistered(c9tOwner);
        Assert.equal(isRegistered, true, "registration error");

        // Check registration data stored matches
        uint96 regData = c9t.getRegistrationFor(c9tOwner);
        Assert.equal(regData, uint96(bytes12(ksig)), "regData error");
    }

    function checkRegistration1()
    public {
        // Grant redeemer role to get registration data
        _grantRole(keccak256("REDEEMER_ROLE"), c9tOwner);
        bytes32 ksig = keccak256(abi.encodePacked(block.timestamp));
        _checkRegistration(ksig, false);
    }

    function checkRegistration2()
    public {
        bytes32 ksig = keccak256(abi.encodePacked("some random data"));
        _checkRegistration(ksig, true);
    }

}