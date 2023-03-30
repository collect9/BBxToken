// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract TransfersTest is C9TestContract {

    address private _to = TestsAccounts.getAccount(1);
    address private _to2 = TestsAccounts.getAccount(2);

    function afterEach()
    public override {
        super.afterEach();
        _checkOwnerDataOf(_to);
        _checkOwnerDataOf(_to2);
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
     */ 
    function checkTransfer1()
    public {
        uint256 mintId = _timestamp % (_rawData.length-4);
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);

        c9t.transferFrom(c9tOwner, _to, tokenId);

        // Make sure new owner is correct
        Assert.equal(c9t.ownerOf(tokenId), _to, "Invalid new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, 1, numVotes);
        _updateTokenTruth(tokenId, _to);

        // Compare against
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    /* @dev 2. Check to ensure optimized batch transfer works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkTransferBatch()
    public {
        uint256[] memory mintIds = new uint256[](2);
        mintIds[0] = (_timestamp + 1) % (_rawData.length-4);
        mintIds[1] = (_timestamp + 2) % (_rawData.length-4);
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);

        // Make sure new owner is correct
        c9t.transferBatchFrom(c9tOwner, _to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(c9t.ownerOf(tokenIds[i]), _to, "Invalid new owner");
            _updateTokenTruth(tokenIds[i], _to);
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, tokenIds.length, numVotes);
        
        // Compare against
        _checkTokenParams(mintIds[0]);
        _checkOwnerParams(mintIds[0]);
        _checkTokenParams(mintIds[1]);
        _checkOwnerParams(mintIds[1]);
    }

    /* @dev 3. Check to ensure optimized safeTransfer works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransfer()
    public {
        uint256 mintId = (_timestamp + 3) % (_rawData.length-4);
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);

        c9t.safeTransferFrom(c9tOwner, _to, tokenId);

        // Make sure new owner is correct
        Assert.equal(c9t.ownerOf(tokenId), _to, "Invalid new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, 1, numVotes);
        _updateTokenTruth(tokenId, _to);

        // Compare against
        _checkTokenParams(mintId);
        _checkOwnerParams(mintId);
    }

    /* @dev 4. Check to ensure optimized batch safeTransferBatch works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransferBatch()
    public {
        uint256[] memory mintIds = new uint256[](2);
        mintIds[0] = (_timestamp + 4) % (_rawData.length-4);
        mintIds[1] = (_timestamp + 5) % (_rawData.length-4);
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);

        c9t.safeTransferBatchFrom(c9tOwner, _to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(c9t.ownerOf(tokenIds[i]), _to, "Invalid new owner");
            _updateTokenTruth(tokenIds[i], _to);
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, _to, tokenIds.length, numVotes);
        
        // Compare against
        _checkTokenParams(mintIds[0]);
        _checkOwnerParams(mintIds[0]);
        _checkTokenParams(mintIds[1]);
        _checkOwnerParams(mintIds[1]);
    }

    /* @dev 5. Check to ensure optimized batch safeTransferBatchAddress works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransferBatchAddress()
    public {
        address[] memory toBatch = new address[](2);
        toBatch[0] = _to;
        toBatch[1] = _to2;

        uint256[] memory mintIdsTo1 = new uint256[](2);
        mintIdsTo1[0] = (_timestamp + 6) % (_rawData.length-4);
        mintIdsTo1[1] = (_timestamp + 7) % (_rawData.length-4);
        (uint256[] memory tokenIdsTo1, uint256 numVotesTo1) = _getTokenIdsVotes(mintIdsTo1);

        uint256[] memory mintIdsTo2 = new uint256[](1);
        mintIdsTo2[0] = (_timestamp + 8) % (_rawData.length-4);
        (uint256[] memory tokenIdsTo2, uint256 numVotesTo2) = _getTokenIdsVotes(mintIdsTo2);

        uint256[][] memory tokenIds = new uint256[][](2);
        tokenIds[0] = tokenIdsTo1;
        tokenIds[1] = tokenIdsTo2;

        c9t.safeBatchTransferBatchFrom(c9tOwner, toBatch, tokenIds);

        // Make sure new owners are correct
        for (uint256 j; j<toBatch.length; j++) {
            for (uint256 i; i<tokenIds[j].length; ++i) {
                Assert.equal(c9t.ownerOf(tokenIds[j][i]), toBatch[j], "Invalid new owner");
                _updateTokenTruth(tokenIds[j][i], toBatch[j]);
            }
        }

        // Better update
        _updateBalancesTruth(c9tOwner, toBatch[0], tokenIds[0].length, numVotesTo1);
        _updateBalancesTruth(c9tOwner, toBatch[1], tokenIds[1].length, numVotesTo2);
        
        // Compare against
        _checkTokenParams(mintIdsTo1[0]);
        _checkOwnerParams(mintIdsTo1[0]);
        _checkTokenParams(mintIdsTo1[1]);
        _checkOwnerParams(mintIdsTo1[1]);
        _checkTokenParams(mintIdsTo2[0]);
        _checkOwnerParams(mintIdsTo2[0]);
    }
}