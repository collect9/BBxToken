// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Token2.sol";

interface IC9Registrar {
    function addressRegistered(address _address) external view returns(bool);
    function cancel() external;
    function getStep(address _address) external view returns(uint256);
    function start() external;
}

contract C9Registrar is IC9Registrar, C9OwnerControl {
    uint96 private _incrementer = uint96(block.number);
    address public immutable contractToken;
    mapping(address => uint32[3]) private _registrationData; //step, code, isRegistered
    
    event RegistrarAdminApprove(
        address indexed tokenOwner
    );
    event RegistrarCancel(
        address indexed tokenOwner,
        uint32 indexed processStep
    );
    event RegistrarInitCode(
        address indexed tokenOwner
    );
    event RegistrarUserVerify(
        address indexed tokenOwner
    );

    constructor(address _contractToken) {
        contractToken = _contractToken;
    }

    modifier isOwner(address _address) {
        // Will revert if not an owner
        C9Token(contractToken).tokenOfOwnerByIndex(_address, 0);
        _;
    }

    modifier isRegistered(address _address) {
        if (_registrationData[_address][2] != 1) {
            _errMsg("token not registered");
        }
        _;
    }

    modifier registrationStep(address _address, uint256 _step) {
        if (_step != _registrationData[_address][0]) {
            _errMsg("wrong process step");
        }
        _;
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Registrar: ", message)));
    }

    function _removeRegistrationData(address _address)
        internal {
            delete _registrationData[_address];
    }

    function addressRegistered(address _address)
        external view override
        returns (bool) {
            return _registrationData[_address][2] == 1;
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     * Cost: ~25,000 gas
     */
    function cancel()
        external override {
            uint32 lastStep = _registrationData[msg.sender][0];
            if (lastStep == 0) {
                _errMsg("caller not in process");
            }
            _removeRegistrationData(msg.sender);
            emit RegistrarCancel(msg.sender, lastStep);
    }

    /**
     * @dev Function the front end will need so it knows which 
     * button to have enabled.
     */
    function getStep(address _address)
        external view override
        returns (uint256) {
            return _registrationData[_address][0];
    }

    /**
     * @dev Step 1. User initializes redemption
     * Cost: ~63,500 gas
     */
    function start()
        external override
        isOwner(msg.sender)
        registrationStep(msg.sender, 0)
        notFrozen() {
            _incrementer += 1;
            uint256 _randomCode = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        block.number,
                        msg.sender,
                        _incrementer
                    )
                )
            ) % 10**6;
            _registrationData[msg.sender][0] = 2;
            _registrationData[msg.sender][1] = uint32(_randomCode);
            emit RegistrarInitCode(msg.sender);
    }
    /**
     * @dev Step 2a. Admin/backend retrieves info.
     */
    function adminGetCode(address _address)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint32) {
            return _registrationData[_address][1];
    }
    
    /**
     * @dev Step 2b. Admin confirms receipt of info by sending code 
     * to email specified in info, along with the rest of the info 
     * for the user to verify.
     * Cost: ~31,000 gas
     */
    function adminVerifyCode(address _address, uint256 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        registrationStep(_address, 2) {
            if (_code != _registrationData[_address][1]) {
                 _errMsg("code mismatch");
            }
            _registrationData[_address][0] = 3;
            emit RegistrarAdminApprove(_address);
    }

    /**
     * @dev Step 3. User verifies info submitted by submitting 
     * confirmation code. This finishes registration.
     * Cost: ~30,000 gas
     */
    function userVerifyCode(uint256 _code)
        external
        registrationStep(msg.sender, 3)
        notFrozen() {
            if (_code != _registrationData[msg.sender][1]) {
                 _errMsg("code mismatch");
            }
            _registrationData[msg.sender][2] = 1;
            emit RegistrarUserVerify(msg.sender);
    }
}