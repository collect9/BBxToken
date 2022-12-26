// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

uint256 constant RPOS_STEP = 0;
uint256 constant RPOS_CODE = 8;
uint256 constant RPOS_BATCHSIZE = 24;
uint256 constant RPOS_TOKEN1 = 32;
uint256 constant UINT_SIZE = 24;
uint256 constant MAX_BATCH_SIZE = 9;

error AddressToFarInProcess(uint256 minStep, uint256 received); //0xb078ecc8
error CancelRemainder(uint256 remainingBatch); //0x2c9f7f1d
error RedeemerBatchSizeTooLarge(uint256 maxSize, uint256 received);
error SizeMismatch(uint256 maxSize, uint256 received); //0x97ce59d2

interface IC9Redeemer {

    function add(address _tokenOwner, uint256[] calldata _tokenId) external;

    function cancel(address _tokenOwner) external returns(uint256 _data);

    function getMinRedeemUSD(uint256 _batchSize) external view returns(uint256);

    function getRedeemerInfo(address _tokenOwner) external view returns(uint256[] memory _info);

    function remove(address _tokenOwner, uint256[] calldata _tokenId) external;

    function start(address _tokenOwner, uint256[] calldata _tokenId) external;
    
}
