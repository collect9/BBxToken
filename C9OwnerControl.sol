// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
* This contract is meant to act as a combination of 
* AccessControl and Ownable (2 step).
*
* onlyRole(DEFAULT_ADMIN_ROLE) is the equivalent of 
* onlyOwner in Ownable. Though note that since it possible 
* to grant more users DEFAULT_ADMIN_ROLE, it is recommended 
* that when giving others access, one one create a lower 
* level of access below the ADMIN i.e, MOD_ROLE.

* The admin renouncing role is the equivalent of 
* renouncing ownership in Ownable.
*
* The admin transferring ownership is the equivalent of 
* 2 step transfer in Ownable. The address accepting ownership 
* is made owner and granted DEFAULT_ADMIN_ROLE.
*
* NOTE: If multiple addresses are granted DEFAULT_ADMIN_ROLE, 
* they cannot revoke owner. Only owner can renounce itself.
*/

abstract contract C9OwnerControl is AccessControl {
    address public owner;
    address public pendingOwner;
    bool _frozen = false;

    event OwnershipTransferCancel(
        address indexed previousOwner
    );
    event OwnershipTransferComplete(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipTransferInit(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        owner = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    modifier notFrozen() { 
        if (_frozen) {
            _errMsg("contract frozen");
        }
        _;
    }

    /**
     * @dev Temp functions.
     */
    function _errMsg(bytes memory message) 
        internal pure virtual {
            revert(string(bytes.concat("C9OwnerControl: ", message)));
    }

    /**
     * @dev It will not be possible to call `onlyRole(DEFAULT_ADMIN_ROLE)` 
     * functions anymore, unless there are other accounts with that role.
     *
     * NOTE: If the renouncer is the original contract owner, the contract 
     * is left without an owner.
     */
    function renounceRole(bytes32 role, address account)
        public override {
            if (account != msg.sender) _errMsg("unauthorized");
            _revokeRole(role, account);
    }

    /**
     * @dev Override that makes it impossible for other admins 
     * to revoke the admin rights of the original contract deployer.
     */
    function revokeRole(bytes32 role, address account)
        public override
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (account == owner) _errMsg("unauthorized");
            _revokeRole(role, account);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function _transferOwnership(address _newOwner)
        internal {
            delete pendingOwner;
            address oldOwner = owner;
            owner = _newOwner;
            revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
            emit OwnershipTransferComplete(oldOwner, _newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function transferOwnership(address _newOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_newOwner == address(0)) _errMsg("invalid address");
            pendingOwner = _newOwner;
            grantRole(DEFAULT_ADMIN_ROLE, _newOwner);
            emit OwnershipTransferInit(owner, _newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer. The original owner will
     * still need to renounceRole DEFAULT_ADMIN_ROLE to fully complete 
     * this process, unless original owner wishes to remain in that role.
     */
    function acceptOwnership()
        external {
            if (pendingOwner != msg.sender) _errMsg("unauthorized");
            _transferOwnership(msg.sender);
    }

    /**
     * @dev Cancels a transfer initiated.
     */
    function cancelTransferOwnership()
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            delete pendingOwner;
            revokeRole(DEFAULT_ADMIN_ROLE, pendingOwner);
            emit OwnershipTransferCancel(owner);
    }

    /**
     * @dev Flag that sets global toggle to freeze redemption. 
     * Users may still cancel redemption and unlock their 
     * token if in the process.
     */
    function toggleFreeze(bool _toggle)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_frozen == _toggle) {
                _errMsg("bool already set");
            }
            _frozen = _toggle;
    }

    function __destroy(address _receiver, bool confirm)
        public virtual
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (confirm) {
    		    selfdestruct(payable(_receiver));
            }
            else {
                _errMsg("destruct not confirmed");
            }
        }
}