// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;
import "./C9BaseDeploy_test.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract TransfersTest is C9TestContract {

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
        address to = TestsAccounts.getAccount(1);
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);

        c9t.transferFrom(c9tOwner, to, tokenId);

        // Make sure new owner is correct
        Assert.equal(to, c9t.ownerOf(tokenId), "Invalid new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, to, 1, numVotes);

        // Compare against
        _checkOwnerDataOf(c9tOwner);
        _checkOwnerDataOf(to);
    }

    /* @dev 2. Check to ensure optimized batch transfer works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkTransferBatch()
    public {
        address to = TestsAccounts.getAccount(1);

        uint256[] memory mintIds = new uint256[](2);
        mintIds[0] = (_timestamp + 1) % _rawData.length;
        mintIds[1] = (_timestamp + 2) % _rawData.length;
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);

        // Make sure new owner is correct
        c9t.transferFrom(c9tOwner, to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(to, c9t.ownerOf(tokenIds[i]), "Invalid new owner");
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, to, tokenIds.length, numVotes);
        
        // Compare against
        _checkOwnerDataOf(c9tOwner);
        _checkOwnerDataOf(to);
    }

    /* @dev 3. Check to ensure optimized safeTransfer works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransfer()
    public {
        address to = TestsAccounts.getAccount(2);
        uint256 mintId = (_timestamp + 3) % _rawData.length;
        (uint256 tokenId, uint256 numVotes) = _getTokenIdVotes(mintId);

        c9t.safeTransferFrom(c9tOwner, to, tokenId);

        // Make sure new owner is correct
        Assert.equal(to, c9t.ownerOf(tokenId), "Invalid new owner");

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, to, 1, numVotes);

        // Compare against
        _checkOwnerDataOf(c9tOwner);
        _checkOwnerDataOf(to);
    }

    /* @dev 4. Check to ensure optimized batch safeTransferBatch works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransferBatch()
    public {
        address to = TestsAccounts.getAccount(2);

        uint256[] memory mintIds = new uint256[](2);
        mintIds[0] = (_timestamp + 4) % _rawData.length;
        mintIds[1] = (_timestamp + 5) % _rawData.length;
        (uint256[] memory tokenIds, uint256 numVotes) = _getTokenIdsVotes(mintIds);

        c9t.safeTransferFrom(c9tOwner, to, tokenIds);

        // Make sure new owner is correct
        for (uint256 i; i<tokenIds.length; ++i) {
            Assert.equal(to, c9t.ownerOf(tokenIds[i]), "Invalid new owner");
        }

        // Ground truth of old and new owner params
        _updateBalancesTruth(c9tOwner, to, tokenIds.length, numVotes);
        
        // Compare against
        _checkOwnerDataOf(c9tOwner);
        _checkOwnerDataOf(to);
    }

    /* @dev 5. Check to ensure optimized batch safeTransferBatchAddress works properly, 
     * with proper owner and new owner data being updated correctly.
     */ 
    function checkSafeTransferBatchAddress()
    public {
        address[] memory toBatch = new address[](2);
        toBatch[0] = TestsAccounts.getAccount(1);
        toBatch[1] = TestsAccounts.getAccount(2);

        uint256[] memory mintIdsTo1 = new uint256[](2);
        mintIdsTo1[0] = (_timestamp + 6) % _rawData.length;
        mintIdsTo1[1] = (_timestamp + 7) % _rawData.length;
        (uint256[] memory tokenIdsTo1, uint256 numVotesTo1) = _getTokenIdsVotes(mintIdsTo1);

        uint256[] memory mintIdsTo2 = new uint256[](1);
        mintIdsTo2[0] = (_timestamp + 8) % _rawData.length;
        (uint256[] memory tokenIdsTo2, uint256 numVotesTo2) = _getTokenIdsVotes(mintIdsTo2);

        uint256[][] memory tokenIds = new uint256[][](2);
        tokenIds[0] = tokenIdsTo1;
        tokenIds[1] = tokenIdsTo2;

        c9t.safeTransferFrom(c9tOwner, toBatch, tokenIds);

        // Make sure new owners are correct
        for (uint256 j; j<toBatch.length; j++) {
            for (uint256 i; i<tokenIds[j].length; ++i) {
                Assert.equal(toBatch[j], c9t.ownerOf(tokenIds[j][i]), "Invalid new owner");
            }
        }

        // Better update
        _updateBalancesTruth(c9tOwner, toBatch[0], tokenIds[0].length, numVotesTo1);
        _updateBalancesTruth(c9tOwner, toBatch[1], tokenIds[1].length, numVotesTo2);
        
        // Compare against
        _checkOwnerDataOf(c9tOwner);
        _checkOwnerDataOf(toBatch[0]);
        _checkOwnerDataOf(toBatch[1]);
    }
}
    