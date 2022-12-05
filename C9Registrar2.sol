// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;
import "./C9OwnerControl.sol";

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

    uint256 private _seed;
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

    constructor(uint256 seed_) {
        _seed = seed_;
    }

    modifier registrationStep(address _address, uint256 _step) {
        uint256 _data = _registrationData[_address];
        if (_step != uint256(uint8(_data>>POS_STEP))) {
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
                _errMsg("address already registered");
            }
            uint256 _code;
            unchecked {
                _code = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            block.number,
                            msg.sender,
                            _seed
                        )
                    )
                ) % 65535;
                _seed += _code;
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
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256) {
            return uint256(uint16(_registrationData[_address]>>POS_CODE));
    }

    /**
     * @dev Step 3.
     * User verifies info submitted by submitting 
     * confirmation code. This finishes registration.
     * Cost: ~27,400 gas
     */
    function userVerifyCode(uint256 _code)
        external
        registrationStep(msg.sender, 2)
        notFrozen() {
            uint256 _data = _registrationData[msg.sender];
            if (_code != uint256(uint16(_data>>POS_CODE))) {
                _errMsg("code mismatch");
            }
            _data |= 1<<POS_REGISTERED;
            _registrationData[msg.sender] = _data;
            emit RegistrarUserVerify(msg.sender);
    }
}