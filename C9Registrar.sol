// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";

uint256 constant GPOS_STEP = 0;
uint256 constant GPOS_CODE = 8;
uint256 constant GPOS_REGISTERED = 24;
uint256 constant REGISTERED = 1;

error AddressAlreadyRegistered(); //0x2d42c772
error AddressNotInProcess(); //0x286d0071
error CodeMismatch(); //0x179708c0
error WrongProcessStep(uint256 expected, uint256 received); //0x58f6fd94

interface IC9Registrar {
    function cancel() external;
    function getStep(address _address) external view returns(uint256);
    function isRegistered(address _address) external view returns(bool);
    function start() external;
}

contract C9Registrar is IC9Registrar, C9OwnerControl {
    bytes32 public constant FRONTEND_ROLE = keccak256("FRONTEND_ROLE");

    mapping(address => uint256) private _registrationData; //step, code, isRegistered
    
    event RegistrarAdminApprove(
        address indexed tokenOwner
    );
    event RegistrarCancel(
        address indexed tokenOwner,
        uint256 indexed processStep
    );
    event RegistrarInit(
        address indexed tokenOwner
    );
    event RegistrarUserVerify(
        address indexed tokenOwner
    );

    constructor() {
        _grantRole(FRONTEND_ROLE, msg.sender); // remove after testing actual frontend
    }

    modifier registrationStep(address _address, uint256 _step) {
        uint256 _data = _registrationData[_address];
        uint256 _expectedStep = uint256(uint8(_data>>GPOS_STEP));
        if (_step != _expectedStep) {
            revert WrongProcessStep(_expectedStep, _step);
        }
        _;
    }

    function _removeRegistrationData(address _address)
        private {
            delete _registrationData[_address];
    }

    function isRegistered(address _address)
        public view override
        returns (bool) {
            return uint256(uint8(_registrationData[_address]>>GPOS_REGISTERED)) == REGISTERED;
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     */
    function cancel()
        external override {
            uint256 _data = _registrationData[msg.sender];
            uint256 lastStep = uint256(uint8(_data>>GPOS_STEP));
            if (lastStep == 0) {
                revert AddressNotInProcess();
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
            uint256 _data = _registrationData[_address];
            return uint256(uint8(_data>>GPOS_STEP));
    }

    /**
     * @dev Step 1.
     * User initializes registration
     */
    function start()
        external override
        registrationStep(msg.sender, 0)
        notFrozen() {
            if (isRegistered(msg.sender)) {
                revert AddressAlreadyRegistered();
            }
            uint256 _code;
            unchecked {
                _code = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            block.number,
                            msg.sender
                        )
                    )
                ) % 65535;
            }
            uint256 _newRegistrationData;
            _newRegistrationData |= 2<<GPOS_STEP;
            _newRegistrationData |= _code<<GPOS_CODE;
            _registrationData[msg.sender] = _newRegistrationData;
            emit RegistrarInit(msg.sender);
    }
    /**
     * @dev Step 2.
     * Admin/backend retrieves info and sends 
     * it along with code to user email.
     */
    function adminGetCode(address _address)
        external view
        onlyRole(FRONTEND_ROLE)
        returns (uint256) {
            return uint256(uint16(_registrationData[_address]>>GPOS_CODE));
    }

    /**
     * @dev Step 3.
     * User verifies info submitted by submitting 
     * confirmation code. This finishes registration.
     * Note that no submitted information is KYC yet.
     * That happens the first time through the redeemer.
     */
    function userVerifyCode(uint256 _code)
        external
        registrationStep(msg.sender, 2)
        notFrozen() {
            uint256 _data = _registrationData[msg.sender];
            if (_code != uint256(uint16(_data>>GPOS_CODE))) {
                revert CodeMismatch();
            }
            _data |= REGISTERED<<GPOS_REGISTERED;
            _registrationData[msg.sender] = _data;
            emit RegistrarUserVerify(msg.sender);
    }
}