// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;
import "./C9OwnerControl.sol";
import "./C9Registrar.sol";
import "./C9Struct.sol";
import "./C9Token2.sol";
import "./utils/EthPricer.sol";

interface IC9Redeemer {
    function add(address _tokenOwner, uint32[] calldata _tokenId) external;
    function cancel(address _tokenOwner) external returns(uint32[] memory _data, uint256 _batchSize);
    function getMinRedeemUsd(uint256 _batchSize) external view returns(uint256);
    function getRedemptionStep(address _tokenOwner) external view returns(uint256);
    function getRedemptionInfo(address _tokenOwner) external view returns(uint32[] memory);
    function remove(address _tokenOwner, uint32[] calldata _tokenId) external;
    function start(address _tokenOwner, uint32[] calldata _tokenId) external;
}

contract C9Redeemer is IC9Redeemer, C9OwnerControl {
    bytes32 public constant NFTCONTRACT_ROLE = keccak256("NFTCONTRACT_ROLE");
    uint96 public redeemMinPrice = 20;
    address public contractPricer;

    mapping(address => uint32[]) redeemerData; //tokenId[], code, step
    
    event RedeemerAdd(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256 indexed newBatchSize
    );
    event RedeemerAdminApprove(
        address indexed tokensOwner
    );
    event RedeemerAdminFinalApproval(
        address indexed tokensOwner
    );
    event RedeemerCancel(
        address indexed tokensOwner,
        uint256 indexed processStep,
        uint256 indexed batchSize
    );
    event RedeemerInit(
        address indexed tokensOwner,
        bool indexed registered,
        uint256 indexed batchSize
    );
    event RedeemerRemove(
        address indexed tokensOwner,
        uint256 indexed existingPending,
        uint256 indexed newBatchSize
    );
    event RedeemerUserFinalize(
        address indexed tokensOwner,
        uint256 indexed fees
    );
    event RedeemerUserVerify(
        address indexed tokensOwner
    );

    address public contractRegistrar;
    address public immutable contractToken;
    
    constructor(address _contractToken) {
        contractToken = _contractToken;
        _grantRole(NFTCONTRACT_ROLE, _contractToken);
    }

    modifier redemptionStep(address _tokenOwner, uint256 _step) {
        if (_step != getRedemptionStep(_tokenOwner)) {
            _errMsg("wrong redemption step");
        }
        _;
    }

    function _errMsg(bytes memory message) 
        internal pure override {
            revert(string(bytes.concat("C9Redeemer: ", message)));
    }

    function _removeRedemptionData(address _tokenOwner)
        internal {
            delete redeemerData[_tokenOwner];
    }

    function add(address _tokenOwner, uint32[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        notFrozen() {
            uint32[] memory _data = redeemerData[_tokenOwner];
            if (_data.length == 0) {
                _errMsg("no batch in process, use start");
            }
            if (_data[0] > 3) {
                _errMsg("current batch too far in process");
            }
            uint256 _existingPending = _data.length-2;
            uint256 _newBatchSize = _tokenId.length+_existingPending;
            if (_newBatchSize > MAX_BATCH_SIZE) {
                _errMsg("max batch size is 22");
            }
            for (uint256 i; i<_tokenId.length; i++) {
                redeemerData[_tokenOwner].push(_tokenId[i]);
            }
            emit RedeemerAdd(_tokenOwner, _existingPending, _newBatchSize);     
    }

    /**
     * @dev
     * Cancels redemption process from the token contract. It 
     * returns the redemption data that contains the list of 
     * tokenId to unlock.
     */
    function cancel(address _tokenOwner)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        returns(uint32[] memory _data, uint256 _batchSize) {
            _data = redeemerData[_tokenOwner];
            if (_data.length == 0) {
                _errMsg("no batch in process");
            }
            _batchSize = _data.length-2;
            _removeRedemptionData(_tokenOwner);
            emit RedeemerCancel(_tokenOwner, _data[0], _data.length-2);
    }

    /*
     * @dev
     * Gets the redemption info/array of _tokenOwner.
     */
    function getRedemptionInfo(address _tokenOwner)
        public view override
        returns(uint32[] memory) {
            return redeemerData[_tokenOwner];
    }

    /*
     * @dev Gets the redemption (batch) _tokenOwner is at.
     */
    function getRedemptionStep(address _tokenOwner)
        public view override
        returns(uint256) {
            uint32[] memory _data = getRedemptionInfo(_tokenOwner);
            return _data.length > 0 ? _data[0] : 0;
    }

    /*
     * @dev
     * Remove individual tokens from the redemption process.
     * This is useful is a tokenOwner only wants to remove a 
     * fraction of tokens in the process. Otherwise it may 
     * end up being more expensive than cancel.
     */
    function remove(address _tokenOwner, uint32[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE) {
            uint32[] memory _data = redeemerData[_tokenOwner];
            uint256 _currentDataLength = _data.length;
            if (_currentDataLength == 0) {
                _errMsg("no batch in process");
            }
            if (_tokenId.length >= _data.length-2) {
                _errMsg("cancel to remove remaining batch");
            }
            /*
            Swap and pop in memory instead of storage. This keeps 
            gas cost down for larger _tokenId arrays.
            */
            for (uint256 i; i<_tokenId.length; i++) {
                for (uint j=2; j<_currentDataLength; j++) {
                    if (_tokenId[i] == _data[j]) {
                        _data[j] = _data[_currentDataLength-1];
                        _currentDataLength -= 1;
                        break;
                    }
                }
            }
            /*
            Copy swapped array and the pop off all removed 
            tokeIds which will appear at the end of the array.
            */
            redeemerData[_tokenOwner] = _data;
            for (uint i; i<_tokenId.length; i++) {
                redeemerData[_tokenOwner].pop();
            }

            emit RedeemerRemove(
                _tokenOwner,
                _data.length-2,
                _data.length-2-_tokenId.length
            );  
    }

    /**
     * @dev Step 1.
     * Token owner initiates redemption process from token contract.
     * The step and code are pushed into the array first for convenience
     * as those are accessed more often throughout the process.
    */
    function start(address _tokenOwner, uint32[] calldata _tokenId)
        external override
        onlyRole(NFTCONTRACT_ROLE)
        redemptionStep(_tokenOwner, 0)
        notFrozen() {
            if (_tokenId.length > MAX_BATCH_SIZE) {
                _errMsg("max batch size is 22");
            }
            bool _registerOwner = IC9Registrar(contractRegistrar).addressRegistered(_tokenOwner);
            uint256 _step = _registerOwner ? 4 : 2;
            uint256 _code = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        block.number,
                        msg.sender
                    )
                )
            ) % 10**6;
            redeemerData[_tokenOwner].push(uint32(_step));
            redeemerData[_tokenOwner].push(uint32(_code));
            for (uint256 i; i<_tokenId.length; i++) {
                redeemerData[_tokenOwner].push(_tokenId[i]);
            }
            emit RedeemerInit(_tokenOwner, _registerOwner, _tokenId.length);     
    }

     /**
     * @dev Step 2a.
     * Admin retrieves code.
     */
    function adminGetRedemptionCode(address _tokenOwner)
        external view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256) {
            return redeemerData[_tokenOwner][1];
    }

    /**
     * @dev Step 2b.
     * Admin confirms user info via front end was received. Code  
     * is emailed to that specified within info, along with the 
     * rest of the info for the user to verify info is correct.
     * Cost: ~38,000 gas
     */
    function adminVerifyRedemptionCode(address _tokenOwner, uint256 _code)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenOwner, 2) {
            if (_code != redeemerData[_tokenOwner][1]) {
                _errMsg("code mismatch");
            }
            redeemerData[_tokenOwner][0] = 3;
            emit RedeemerAdminApprove(_tokenOwner);
    }

    /**
     * @dev Step 3.
     * User verifies their info submitted to the frontend by checking 
     * email confirmation with code, then submitting confirmation code.
     * Cost: ~35,000 gas
     */
    function userVerifyRedemption(uint256 _code)
        external
        redemptionStep(msg.sender, 3) {
            if (_code != redeemerData[msg.sender][1]) {
                _errMsg("code mismatch");
            }
            redeemerData[msg.sender][0] = 4;
            emit RedeemerUserVerify(msg.sender);
    }

    function getMinRedeemUsd(uint256 _batchSize)
        public view override
        returns (uint256) {
            uint256 _n = _batchSize-1;
            uint256 _bps = _n == 0 ? 100 : 98**_n / 10**(_n*2-2);
            return redeemMinPrice*_batchSize*_bps/100;
    }

    /**
     * @dev Step 4.
     * User pays final fees that include insured shipping and 
     * handling costs. 
     * Note: Fee will need to be done externally, as periodically updating 
     * some kind of insured value within the C9Token could get extremely 
     * expensive even using packed data. A test of updating ~256 packed tokens
     * within a single call was estimated to cost ~1.5M gas.
     * Instead, a minimum amount is enforced to be payable. To 
     * prevent users purposely underpaying, an aminFinalApproval 
     * still follows this.
     */
    function userFinishRedemption()
        external payable
        redemptionStep(msg.sender, 4) {
            uint256 _minRedeemUsd = getMinRedeemUsd(redeemerData[msg.sender].length-2);
            // uint256 _minRedeemWei = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_minRedeemUsd);
            // if (msg.value < _minRedeemWei) {
            //     _errMsg("invalid payment amount");
            // }
            // (bool success,) = payable(owner).call{value: msg.value}("");
            // if (!success) {
            //     _errMsg("payment failure");
            // }
            redeemerData[msg.sender][0] = 5;
            emit RedeemerUserFinalize(msg.sender, msg.value);
    }

    /**
     * @dev Step 5.
     * Admin final approval. Admin verifies that all 
     * redemption fees have been paid. Beyond this step, the redemption 
     * user will receive tracking information by the email they provided 
     * in a prior step.
     */
    function adminFinalApproval(address _tokenOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        redemptionStep(_tokenOwner, 5)
        notFrozen() {
            IC9Token(contractToken).redeemFinish(redeemerData[_tokenOwner]);
            _removeRedemptionData(_tokenOwner);
            emit RedeemerAdminFinalApproval(_tokenOwner);
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractPricer == _address) {
                _errMsg("contract already set");
            }
            contractPricer = _address;
    }

    /**
     * @dev Updates the token contract address.
     */
    function setContractRegistrar(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractRegistrar == _address) {
                _errMsg("contract already set");
            }
            contractRegistrar = _address;
    }

    /**
     * @dev Updates the minimum redemption price.
     */
    function setRedeemMinPrice(uint256 _price)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (redeemMinPrice == _price) {
                _errMsg("price already set");
            }
            redeemMinPrice = uint96(_price);
    }


}