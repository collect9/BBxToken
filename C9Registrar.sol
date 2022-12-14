// SPDX-License-Identifier: MIT
pragma solidity >0.8.10;
import "./C9OwnerControl.sol";

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
    uint256 constant POS_STEP = 0;
    uint256 constant POS_CODE = 8;
    uint256 constant POS_REGISTERED = 24;

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
        _grantRole(FRONTEND_ROLE, msg.sender);
    }

    modifier registrationStep(address _address, uint256 _step) {
        uint256 _data = _registrationData[_address];
        uint256 _expectedStep = uint256(uint8(_data>>POS_STEP));
        if (_step != _expectedStep) {
            // _errMsg("wrong process step");
            revert WrongProcessStep(_expectedStep, _step);
        }
        _;
    }

    // function _errMsg(bytes memory message) 
    //     internal pure override {
    //         revert(string(bytes.concat("C9Registrar: ", message)));
    // }

    function _removeRegistrationData(address _address)
        internal {
            delete _registrationData[_address];
    }

    function isRegistered(address _address)
        public view override
        returns (bool) {
            return uint256(uint8(_registrationData[_address]>>POS_REGISTERED)) == 1;
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     * Cost: ~25,000 gas
     */
    function cancel()
        external override {
            uint256 _data = _registrationData[msg.sender];
            uint256 lastStep = uint256(uint8(_data>>POS_STEP));
            if (lastStep == 0) {
                // _errMsg("address not in process");
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
            return uint256(uint8(_data>>POS_STEP));
    }

    /**
     * @dev Step 1.
     * User initializes registration
     * Cost: ~52,600 gas
     */
    function start()
        external override
        registrationStep(msg.sender, 0)
        notFrozen() {
            if (isRegistered(msg.sender)) {
                // _errMsg("address already registered");
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
            _newRegistrationData |= 2<<POS_STEP;
            _newRegistrationData |= _code<<POS_CODE;
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
            return uint256(uint16(_registrationData[_address]>>POS_CODE));
    }

    /**
     * @dev Step 3.
     * User verifies info submitted by submitting 
     * confirmation code. This finishes registration.
     * Note that no submitted information is KYC'd 
     * at this point.
     * Cost: ~30,100 gas
     */
    function userVerifyCode(uint256 _code)
        external
        registrationStep(msg.sender, 2)
        notFrozen() {
            uint256 _data = _registrationData[msg.sender];
            if (_code != uint256(uint16(_data>>POS_CODE))) {
                // _errMsg("code mismatch");
                revert CodeMismatch();
            }
            _data |= 1<<POS_REGISTERED;
            _registrationData[msg.sender] = _data;
            emit RegistrarUserVerify(msg.sender);
    }
}