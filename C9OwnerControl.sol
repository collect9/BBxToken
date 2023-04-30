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
    bytes32 public constant DEFAULT_OWNER_ROLE = keccak256("DEFAULT_OWNER_ROLE");
    
    address public owner;
    address public pendingOwner;
    bool private _frozen;

    event OwnershipTransfer(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(DEFAULT_OWNER_ROLE, _msgSender());
        owner = _msgSender();
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

    /*
     * @dev Required override.
     */ 
    function _msgSender()
    internal view
    override(ERC2771Context, Context)
    returns (address sender) {
        return super._msgSender();
    }

    /*
     * @dev Required override.
     */ 
    function _msgData()
    internal view
    override(ERC2771Context, Context)
    returns (bytes calldata) {
        return super._msgData();
    }

    /**
     * @dev Allows account to renounce current role.
     *
     * @param role The role to renounce.
     * @param account The account to renounce role of.
     * @notice If the renouncer is the original contract owner, the contract 
     * is effectively left without an admin/owner.
     */
    function renounceRole(bytes32 role, address account)
    public override {
        if (account != _msgSender()) revert C9Unauthorized();
        if (!hasRole(role, account)) revert NoRoleOnAccount();
        _revokeRole(role, account);
    }

    /**
     * @dev Override that makes it impossible for other admins 
     * to revoke the admin rights of the contract owner.
     * As a result admin also cannot revoke itself either 
     * but it can still renounce.
     *
     * @param role The role to renounce.
     * @param account The account to renounce role of.
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
     * This is meant to make AccessControl functionally equivalent 
     * to 2-step Ownable.
     *
     * @param newOwner The new owner of the contract.
     * @notice Old owner still has admin role. That needs to either be renounced 
     * or revoked by the new owner.
     * @notice Emits an ownership transfer event.
     */
    function _transferOwnership(address newOwner)
    private {
        delete pendingOwner;
        address _oldOwner = owner;
        owner = newOwner;
        // 1. Grant owner and admin roles to new owner
        _grantRole(DEFAULT_OWNER_ROLE, newOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        // 2. Remove owner role from old owner
        _revokeRole(DEFAULT_OWNER_ROLE, _oldOwner);
        emit OwnershipTransfer(_oldOwner, newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * This can only be called by the current owner.
     *
     * @param newOwner The new owner of the contract.
     */
    function transferOwnership(address newOwner)
    external
    onlyRole(DEFAULT_OWNER_ROLE)
    validTo(newOwner) {
        pendingOwner = newOwner;
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership()
    external {
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
    onlyRole(DEFAULT_OWNER_ROLE) {
        if (pendingOwner == address(0)) revert NoTransferPending();
        delete pendingOwner;
    }

    /**
     * @dev Set the trusted forwarder of the contract.
     *
     * @param forwarder The address of the forwarder.
     */
    function setTrustedForwarder(address forwarder)
    external
    onlyRole(DEFAULT_OWNER_ROLE)
    addressNotSame(_trustedForwarder, forwarder) {
        _trustedForwarder = forwarder;
    }

    /**
     * @dev Flag that sets global toggle to freeze functionality. 
     * For method that have the freeze modifier.
     *
     * @param toggle Freeze (true) or unfreeze (false).
     */
    function toggleFreeze(bool toggle)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frozen == toggle) {
            revert BoolAlreadySet();
        }
        _frozen = toggle;
    }

    /**
     * @dev Allows for contract to be destroyed. The virtual flag
     * allows this to be overriden and disabled.
     *
     * @param receiver The address to receive any remaining balance.
     * @param confirm Confirmation of destruction of the contract.
     * @notice This will eventually be deprecated and not work.
     */
    function __destroy(address receiver, bool confirm)
    public virtual
    onlyRole(DEFAULT_OWNER_ROLE) {
        if (!confirm) {
            revert ActionNotConfirmed();
        }
        selfdestruct(payable(receiver));
    }
}