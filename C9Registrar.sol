// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./interfaces/IC9Registrar.sol";

contract C9Registrar is IC9Registrar, C9OwnerControl {
    bytes32 public constant VIEWER_ROLE = keccak256("FRONTEND_ROLE");

    mapping(address => bytes32) private _registrationData;

    event RegistrarAdd(
        address indexed tokenOwner
    );
    event RegistrarRemove(
        address indexed tokenOwner
    );

    constructor() {
        _grantRole(VIEWER_ROLE, msg.sender);
    }

    /**
     * @dev Adds address registration.
     */
    function add(bytes32 _ksig32, bool _replace)
        external override
        notFrozen() {
            if (isRegistered(msg.sender) && !_replace) {
                revert AddressAlreadyRegistered();
            }
            _registrationData[msg.sender] = _ksig32;
            emit RegistrarAdd(msg.sender);
    }

    /**
     * @dev Gets the hashed signature data.
     */
    function getDataFor(address _address)
        external view override
        onlyRole(VIEWER_ROLE)
        returns (bytes32 data) {
            data = _registrationData[_address];
    }

    /**
     * @dev Returns whether or not the address is registered.
     */
    function isRegistered(address _address)
        public view override
        returns (bool registered) {
            registered = _registrationData[_address] != bytes32(0);
    }

    /**
     * @dev Removes address registration.
     */
    function remove()
        external override {
            if (!isRegistered(msg.sender)) {
                revert AddressNotInProcess();
            }
            delete _registrationData[msg.sender];
            emit RegistrarRemove(msg.sender);
    }
}