// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../abstract/C9Errors.sol";
import "./../utils/C9ERC2771Context.sol";

abstract contract C9BasicOwnable is ERC2771Context {

    bool internal _frozen;
    address private _owner;

    constructor() {
        _owner = _msgSender();
    }

    modifier onlyOwner() {
        if (_msgSender() != _owner) {
            revert Unauthorized();
        }
        _;
    }

    modifier notFrozen() {
        if (_frozen) {
            revert ContractFrozen();
        }
        _;
    }

    function toggleFreeze(bool toggle)
    external
    onlyOwner {
        if (toggle == _frozen) {
            revert BoolAlreadySet();
        }
        _frozen = toggle;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function transferOwnership(address newOwner)
    external
    onlyOwner {
        if (newOwner == address(0)) {
            revert ZeroAddressError();
        }
        _owner = newOwner;
    }
}