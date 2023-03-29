// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./utils/C9ERC2771Context.sol";
import "./abstract/C9Errors.sol";

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

abstract contract C9OwnerControl is AccessControl, ERC2771Context {
    address public owner;
    address public pendingOwner;
    bool _frozen;

    event OwnershipTransfer(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        owner = _msgSender();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /*
     * @dev Checks if address is the same before update. There are 
     * a few functions that update addresses where this is used.
     */ 
    modifier addressNotSame(address old, address _new) {
        if (old == _new) {
            revert AddressAlreadySet();
        }
        _;
    }

    /*
     * @dev Check to see if contract is frozen.
     */ 
    modifier notFrozen() { 
        if (_frozen) {
            revert ContractFrozen();
        }
        _;
    }

    /*
     * @dev Checks to see set addres is not the zero address.
     */ 
    modifier validTo(address to) {
        if (to == address(0)) {
            revert ZeroAddressError();
        }
        _;
    }

    function _msgSender()
    internal view
    override(ERC2771Context, Context)
    returns (address sender) {
        return super._msgSender();
    }

    function _msgData()
    internal view
    override(ERC2771Context, Context)
    returns (bytes calldata) {
        return super._msgData();
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
            if (account != _msgSender()) revert C9Unauthorized();
            if (!hasRole(role, account)) revert NoRoleOnAccount();
            _revokeRole(role, account);
    }

    /**
     * @dev Override that makes it impossible for other admins 
     * to revoke the admin rights of the original contract deployer.
     * As a result admin also cannot revoke itself either.
     * But it can still renounce.
     */
    function revokeRole(bytes32 role, address account)
        public override
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (account == owner) revert C9Unauthorized();
            if (!hasRole(role, account)) revert NoRoleOnAccount();
            _revokeRole(role, account);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction. This is meant to make AccessControl 
     * functionally equivalent to 2-step Ownable.
     */
    function _transferOwnership(address _newOwner)
        private {
            delete pendingOwner;
            address _oldOwner = owner;
            owner = _newOwner;
            _grantRole(DEFAULT_ADMIN_ROLE, _newOwner);
            _revokeRole(DEFAULT_ADMIN_ROLE, _oldOwner);
            emit OwnershipTransfer(_oldOwner, _newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function transferOwnership(address _newOwner)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    validTo(_newOwner)
    notFrozen() {
        pendingOwner = _newOwner;
    }

    /**
     * @dev The new owner accepts the ownership transfer. The original owner will
     * still need to renounceRole DEFAULT_ADMIN_ROLE to fully complete 
     * this process, unless original owner wishes to remain in that role.
     */
    function acceptOwnership()
        external
        notFrozen() {
            if (pendingOwner != _msgSender()) revert C9Unauthorized();
            if (pendingOwner == address(0)) revert NoTransferPending();
            _transferOwnership(pendingOwner);
    }

    /**
     * @dev Cancels a transfer initiated. Although it may make sense to let
     * pending owner do this as well, we're keeping it ADMIN only.
     */
    function cancelTransferOwnership()
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (pendingOwner == address(0)) revert NoTransferPending();
            delete pendingOwner;
    }

    /**
     * @dev Set the trusted forwarder of the contract.
     */
    function setTrustedForwarder(address forwarder)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        addressNotSame(_trustedForwarder, forwarder) {
            _trustedForwarder = forwarder;
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
                revert BoolAlreadySet();
            }
            _frozen = _toggle;
    }

    function __destroy(address _receiver, bool confirm)
        public virtual
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (!confirm) {
                revert ActionNotConfirmed();
            }
    		selfdestruct(payable(_receiver));
        }
}