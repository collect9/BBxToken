// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
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

error ActionNotConfirmed(); //0xacdb9fab
error BoolAlreadySet(); //0xf04e4fd9
error ContractFrozen(); //0x4051e961
error NoRoleOnAccount(); //0xb1a60829
error NoTransferPending(); //0x9c6b0866
error C9Unauthorized(); //0xa020ddad
error C9ZeroAddressInvalid(); //0x7c7fa4fb

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
            revert ContractFrozen();
        }
        _;
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
            if (account != msg.sender) revert C9Unauthorized();
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
            emit OwnershipTransferComplete(_oldOwner, _newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function transferOwnership(address _newOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        notFrozen() {
            if (_newOwner == address(0)) revert C9ZeroAddressInvalid();
            pendingOwner = _newOwner;
            emit OwnershipTransferInit(owner, _newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer. The original owner will
     * still need to renounceRole DEFAULT_ADMIN_ROLE to fully complete 
     * this process, unless original owner wishes to remain in that role.
     */
    function acceptOwnership()
        external
        notFrozen() {
            if (pendingOwner != msg.sender) revert C9Unauthorized();
            if (pendingOwner == address(0)) revert NoTransferPending();
            _transferOwnership(msg.sender);
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