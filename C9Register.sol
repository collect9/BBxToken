// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Registrar {    
    function cancel(uint256 _tokenId) external;
    function clearRegistrationInfo(uint256 _tokenId) external;
    function getRegisteredOwner(uint256 _tokenId) external view returns (address);
    function getStep(uint256 _tokenId) external view returns(uint8);
    function start(uint256 _tokenId) external;
}

contract C9Registrar is IC9Registrar, C9OwnerControl {
    bool _frozen;
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    
    mapping(uint256 => uint32) private _verificationCode;
    mapping(uint256 => uint8) private _processStep;
    mapping(uint256 => address) private _pendingOwner;
    mapping(uint256 => address) private _registeredOwner;
    
    event RegistrarAdminApprove(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RegistrarCancel(
        uint256 indexed tokenId,
        address indexed tokenOwner,
        uint8 indexed processStep
    );
    event RegistrarGenCode(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RegistrarInit(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RegistrarUserVerify(
        uint256 indexed tokenId,
        address indexed tokenOwner
    );
    event RegistrarTransferComplete(
        address indexed previousOwner,
        address indexed newOwner
    );
    event RegistrarTransferInit(
        address indexed previousOwner,
        address indexed newOwner
    );
    event RegistrarTransferCancel(
        address indexed previousOwner
    );

    address public tokenContract;

    constructor(){}

    modifier isOwner(uint256 _tokenId) {
        address _tokenOwner = IC9Token(tokenContract).ownerOf(_tokenId);
        if (msg.sender != _tokenOwner) revert("C9Registrar: unauthorized");
        _;
    }

    modifier isRegistered(uint256 _tokenId) {
        if (_registeredOwner[_tokenId] == address(0)) revert("C9Registrar: token not registered");
        _;
    }

    modifier notFrozen() {
        if (_frozen) revert("C9Registrar: contract frozen");
        _;
    }

    modifier processStep(uint256 _tokenId, uint8 _step) {
        uint32 _expected = _processStep[_tokenId];
        if (_step != _expected) revert("C9Registrar: wrong process step");
        _;
    }

    /**
     * @dev If a user cancels/unlocks token in main contract, the info 
     * here needs to removed as well. The token contract will call this 
     * function upon cancel/unlock.
     */
    function cancel(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE) {
            _removeTokenInfo(_tokenId, true, true);
            emit RegistrarCancel(_tokenId, msg.sender, _processStep[_tokenId]);
    }

    /**
     * @dev Function the front end will need so it knows which 
     * button to have enabled.
     */
    function getStep(uint256 _tokenId)
        external view override
        returns (uint8) {
            return _processStep[_tokenId];
    }

    /**
     * @dev Step 1. User initializes redemption
     */
    function start(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        processStep(_tokenId, 0)
        notFrozen() {
            _processStep[_tokenId] = 1;
            emit RegistrarInit(_tokenId, msg.sender);
    }

    /**
     * @dev Step 2. User submits info and waits for email.
     */
    function userGenCode(uint256 _tokenId)
        external
        isOwner(_tokenId)
        processStep(_tokenId, 1)
        notFrozen() {
            uint32 _randomCode = uint32(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            block.number,
                            msg.sender
                        )
                    )
                )
            ) % 10**6;
            _verificationCode[_tokenId] = _randomCode;
            _processStep[_tokenId] = 2;
            emit RegistrarGenCode(_tokenId, msg.sender);
    }

    /**
     * @dev Step 3a. Admin/backend retrieves info.
     */
    function adminGetCode(uint256 _tokenId)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        processStep(_tokenId, 2)
        returns (uint32) {
            return _verificationCode[_tokenId];
    }
    /**
     * @dev Step 3b. Admin confirms receipt of info by sending code 
     * to email specified in info, along with the rest of the info 
     * for the user to verify.
     */
    function adminVerifyCode(uint256 _tokenId, uint32 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        processStep(_tokenId, 2) {
            if (_code != _verificationCode[_tokenId]) {
                revert("C9Registrar: code incorrect");
            }
            _processStep[_tokenId] = 3;
            address _tokenOwner = IC9Token(tokenContract).ownerOf(_tokenId);
            emit RegistrarAdminApprove(_tokenId, _tokenOwner);
    }

    /**
     * @dev Step 4. User verifies info submitted by submitting 
     * confirmation code. This finishes registration.
     */
    function userVerifyCode(uint256 _tokenId, uint32 _code)
        external
        isOwner(_tokenId)
        processStep(_tokenId, 3)
        notFrozen() {
            if (_code != _verificationCode[_tokenId]) {
                revert("C9Registrar: code incorrect");
            }
            _removeTokenInfo(_tokenId, false, false);
            _registeredOwner[_tokenId] = msg.sender;
            emit RegistrarUserVerify(_tokenId, msg.sender);
    }

    function _removeTokenInfo(uint256 _tokenId, bool keepRegistered, bool keepPending)
        internal {
            delete _processStep[_tokenId];
            delete _verificationCode[_tokenId];
            if (!keepRegistered) delete _registeredOwner[_tokenId];
            if (!keepPending) delete _pendingOwner[_tokenId];
    }

    function clearRegistrationInfo(uint256 _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE) {
            _removeTokenInfo(_tokenId, false, false);
    }

    function getRegisteredOwner(uint256 _tokenId)
        external view override
        returns (address) {
            return _registeredOwner[_tokenId];        
    }

    /**
     * @dev Updates the token contract address.
     */
    function setTokenContract(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (tokenContract == _address) {
                revert("C9Registrar: address already set");
            }
            tokenContract = _address;
            _grantRole(NFTCONTRACT_ROLE, tokenContract);
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
                revert("C9Registrar: bool already set");
            }
            _frozen = _toggle;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function _transferRegistration(uint256 _tokenId, address _newOwner)
        internal {
            address _oldOwner = _registeredOwner[_tokenId];
            _registeredOwner[_tokenId] = _newOwner;
            delete _pendingOwner[_tokenId];
            emit RegistrarTransferComplete(_oldOwner, _newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner. This is meant to make AccessControl 
     * functionally equivalent to Ownable.
     */
    function transferRegistraton(uint256 _tokenId, address _newOwner)
        external
        isOwner(_tokenId)
        isRegistered(_tokenId)
        notFrozen() {
            if (_newOwner == address(0)) revert("C9Registrar: Invalid address");
            _pendingOwner[_tokenId] = _newOwner;
            emit RegistrarTransferInit(msg.sender, _newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer. The original owner will
     * still need to renounceRole DEFAULT_ADMIN_ROLE to fully complete 
     * this process, unless original owner wishes to remain in that role.
     */
    function acceptRegistration(uint256 _tokenId)
        external
        isRegistered(_tokenId)
        notFrozen() {
            address _newOwner = _pendingOwner[_tokenId];
            if (_newOwner != msg.sender) revert("C9Registrar: Unauthorized");
            _transferRegistration(_tokenId, _newOwner);
    }

        /**
     * @dev The new owner accepts the ownership transfer. The original owner will
     * still need to renounceRole DEFAULT_ADMIN_ROLE to fully complete 
     * this process, unless original owner wishes to remain in that role.
     */
    function cancelTransferRegistraton(uint256 _tokenId)
        external
        isOwner(_tokenId) {
            delete _pendingOwner[_tokenId];
            emit RegistrarTransferCancel(msg.sender);
    }
}