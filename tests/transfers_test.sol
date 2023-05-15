// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract TransfersTest is C9TestContract {

    address private _to = TestsAccounts.getAccount(1);
    address private _to2 = TestsAccounts.getAccount(2);
    address private _to3 = TestsAccounts.getAccount(3);
    uint256 private _mintIdOffset;

    uint256 constant MAX_MINT_ID = DATA_SIZE - 4;

    function afterEach()
    public override {
        super.afterEach();
        _checkOwnerDataOf(_to);
        _checkOwnerDataOf(_to2);
        _checkOwnerDataOf(_to3); // Dummy account
    }

    function _updateTokenTruth(uint256 tokenId, address to)
    private {
        ++tokenTransfers[tokenId];
        tokenOwner[tokenId] = to;
    }

    function _updateBalancesTruth(address from, address to, uint256 numTokens, uint256 numVotes)
    private {
        balances[from] -= numTokens;
        transfers[from] += numTokens;
        votes[from] -= numVotes;
        balances[to] += numTokens;
        transfers[to] += numTokens;
        votes[to] += numVotes;
    }

    /* @dev 1. Check to ensure optimized transfer works properly, 
     * with proper owner and new owner data being updated correctly.
     * Max transfer after this step = 1.
     */ 
    function checkTransfer1()
    public {
        uint256 mintId = _timestamp % MAX_MINT_ID;
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);
        _mintIdOffset += 1;

        c9t.transferFrom(c9tOwner, _to, tokenId);

        // Make sure new owner is correct
        Assert.equal(c9t.ownerOf(tokenId), _to, "X new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, 1, numVotes);
        _updateTokenTruth(tokenId, _to);
    }

    /* @dev 2. Check to ensure optimized batch transfer works properly, 
     * with proper owner and new owner data being updated correctly.
     * Max transfer after this step = 4.
     */ 
    function checkTransferBatch()
    public {
        // Pick random number of tokens to transfer
        uint256 numberToTransfer = _timestamp % 3 + 1;
        uint256[] memory mintIds = new uint256[](numberToTransfer);
        for (uint256 i; i<numberToTransfer; i++) {
            mintIds[i] = (_timestamp + i + _mintIdOffset) % MAX_MINT_ID;
        }
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);
        _mintIdOffset += numberToTransfer;

        // Make sure new owner is correct
        c9t.transferBatchFrom(c9tOwner, _to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(c9t.ownerOf(tokenIds[i]), _to, "X new owner");
            _updateTokenTruth(tokenIds[i], _to);
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, tokenIds.length, numVotes);
    }

    /* @dev 3. Check to ensure optimized safeTransfer works properly, 
     * with proper owner and new owner data being updated correctly.
     * Max transfer after this step = 5.
     */ 
    function checkSafeTransfer()
    public {
        uint256 mintId = (_timestamp + _mintIdOffset) % MAX_MINT_ID;
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);
        _mintIdOffset += 1;

        c9t.safeTransferFrom(c9tOwner, _to, tokenId);

        // Make sure new owner is correct
        Assert.equal(c9t.ownerOf(tokenId), _to, "X new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, 1, numVotes);
        _updateTokenTruth(tokenId, _to);
    }

    /* @dev 4. Check to ensure optimized batch safeTransferBatch works properly, 
     * with proper owner and new owner data being updated correctly.
     * Max transfer after this step = 9.
     */ 
    function checkSafeTransferBatch()
    public {
        uint256 numberToTransfer = _timestamp % 4 + 1;
        uint256[] memory mintIds = new uint256[](numberToTransfer);

        for (uint256 i; i<numberToTransfer; i++) {
            mintIds[i] = (_timestamp + i + _mintIdOffset) % MAX_MINT_ID;
        }
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);

        c9t.safeTransferBatchFrom(c9tOwner, _to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(c9t.ownerOf(tokenIds[i]), _to, "X new owner");
            _updateTokenTruth(tokenIds[i], _to);
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, tokenIds.length, numVotes);

        _mintIdOffset += numberToTransfer;
    }

    /* @dev 5. Check to ensure optimized batch safeTransferBatchAddress works properly, 
     * with proper owner and new owner data being updated correctly.
     * Max transfer after this step = 16.
     */
    function checkSafeTransferBatchAddress()
    public {
        uint256 numberToTransferTo1 = _timestamp % 3 + 1;
        uint256 numberToTransferTo2 = uint256(keccak256(abi.encodePacked(
            numberToTransferTo1,
            _timestamp,
            msg.sender
        ))) % 4 + 1;

        address[] memory toBatch = new address[](2);
        toBatch[0] = _to;
        toBatch[1] = _to2;

        uint256[] memory mintIdsTo1 = new uint256[](numberToTransferTo1);
        for (uint256 i; i<numberToTransferTo1; i++) {
            mintIdsTo1[i] = (_timestamp + i + _mintIdOffset) % MAX_MINT_ID;
        }
        (uint256[] memory tokenIdsTo1, uint256 numVotesTo1) = _getTokenIdsVotes(mintIdsTo1);
        _mintIdOffset += numberToTransferTo1;

        uint256[] memory mintIdsTo2 = new uint256[](numberToTransferTo2);
        for (uint256 i; i<numberToTransferTo2; i++) {
            mintIdsTo2[i] = (_timestamp + i + _mintIdOffset) % MAX_MINT_ID;
        }
        (uint256[] memory tokenIdsTo2, uint256 numVotesTo2) = _getTokenIdsVotes(mintIdsTo2);
        _mintIdOffset += numberToTransferTo2;

        uint256[][] memory tokenIds = new uint256[][](2);
        tokenIds[0] = tokenIdsTo1;
        tokenIds[1] = tokenIdsTo2;

        c9t.safeBatchTransferBatchFrom(c9tOwner, toBatch, tokenIds);

        // Make sure new owners are correct
        for (uint256 j; j<toBatch.length; j++) {
            for (uint256 i; i<tokenIds[j].length; ++i) {
                Assert.equal(c9t.ownerOf(tokenIds[j][i]), toBatch[j], "X new owner");
                _updateTokenTruth(tokenIds[j][i], toBatch[j]);
            }
        }

        // Better update
        _updateBalancesTruth(c9tOwner, toBatch[0], tokenIds[0].length, numVotesTo1);
        _updateBalancesTruth(c9tOwner, toBatch[1], tokenIds[1].length, numVotesTo2);
    }
}