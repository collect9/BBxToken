// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./utils/C9ERC2771Context.sol";
import "./abstract/C9Errors.sol";

/**
* This contract is meant to act as a combination of 
* AccessControl and Ownable (2 step).
*
* onlyRole(DEFAULT_OWNER_ROLE) is the equivalent of 
* onlyOwner in Ownable.
*
* onlyRole(DEFAULT_ADMIN_ROLE) is one level below it, 
* meant to offer most contract control but without ownership 
* control.
*
* The owner renouncing DEFAULT_OWNER_ROLE is the equivalent of 
* renouncing ownership in Ownable. But it will still have 
* DEFAULT_ADMIN_ROLE, which must also be renounced to remove 
* full control.
*
* The admin transferring ownership is the equivalent of 
* 2 step transfer in Ownable. The address accepting ownership 
* is made owner and granted owner.
*
* NOTE: DEFAULT_ADMIN_ROLE can grant all roles except DEFAULT_OWNER_ROLE.
* DEFAULT_OWNER_ROLE can only be transfer or renounced.
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
        _setContractOwner(_msgSender());
    }

    /*
     * @dev Checks if address is the same before update. There are 
     * a few functions that update addresses where this is used.
     *
     * @param old The old address.
     * @param _new The new address.
     * @notice This modifier is defined here for inheriting 
     * contracts despite only being called once in this one.
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
     *
     * @param to The account to check.
     * @notice This modifier is defined here for inheriting 
     * contracts despite only being called once in this one.
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

    /*
     * @dev Removes role from account.
     *
     * @param role The account role.
     * @param account The account to remove role from.
     */ 
    function _removeRole(bytes32 role, address account)
    private {
        _roleOnAccountExists(role, account);
        _revokeRole(role, account);
    }

    /*
     * @dev Checks if the account has role.
     *
     * @param role The account role.
     * @param account The account to check if role is on.
     */ 
    function _roleOnAccountExists(bytes32 role, address account)
    private view {
        if (!hasRole(role, account)) {
            revert NoRoleOnAccount();
        }
    }

    /*
     * @dev Sets new contract owner. Makes sure 
     * the owner has both top-level owner and 
     * admin-level priveleges.
     *
     * @param account The account to set contract owner to.
     */
    function _setContractOwner(address account)
    private {
        _grantRole(DEFAULT_OWNER_ROLE, account);
        _grantRole(DEFAULT_ADMIN_ROLE, account);
        owner = account;
    }

    /*
     * @dev Checks to make sure the role being 
     * granted or set is allowed. All roles except 
     * the DEFAULT_OWNER_ROLE are settable.
     *
     * @param role The role to check.
     */
    function _validRole(bytes32 role)
    private pure {
        if (role == DEFAULT_OWNER_ROLE) {
            revert OwnerRoleMustBeTransfer();
        }
    }

    /**
     * @dev Override that checks if the role 
     * being set is a valid role.
     *
     * @param role The role to set.
     * @param account The address to assign the role to.
     */
    function grantRole(bytes32 role, address account)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE) {
        _validRole(role);
        _grantRole(role, account);
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
    public
    override {
        if (account != _msgSender()) revert C9Unauthorized();
        _removeRole(role, account);
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
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == _msgSender()) revert CannotRevokeSelf();
        if (account == owner) revert C9Unauthorized();
        _removeRole(role, account);
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
        _setContractOwner(newOwner);
        // 2. Remove owner role from old owner (admin role still remains)
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
     * @notice This functionality to set to admin which the owner 
     * also has.
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