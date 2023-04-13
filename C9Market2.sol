// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// import "./C9OwnerControl.sol";
import "./interfaces/IC9Token.sol";
import "./utils/C9Signer.sol";
import "./utils/C9BasicOwnable.sol";
import "./utils/Helpers.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

contract C9Market is C9Signer, C9BasicOwnable {
    //keccak256("ListingRequest(address from,uint256 tokenId,uint256 price,uint256 expiry)");.
    bytes32 constant public LISTING_HASH = 0xfd82c467e66ad82c85604b262428614d2828867d6db0c28657044d9c4aefc226;
    
    address private _contractPriceFeed;
    address private immutable _contractToken;
    bytes32 private immutable nameHash;
    bytes32 private immutable versionHash;

    event Purchase(
        address indexed purchaser,
        uint256 indexed price,
        uint256 indexed tokenId
    );

    constructor(
        address contractPriceFeed,
        address contractToken
    ) {
        // Linking contracts
        _contractPriceFeed = contractPriceFeed;
        _contractToken = contractToken;
        // Signature defaults
        nameHash = keccak256(bytes("Collect9 NFT Store"));
        versionHash = keccak256(bytes("1"));
    }

    /**
     * @dev Checks to make sure payment amount is correct and payment 
     * transfer is successful.
     */
    function _makePayment(address from, uint256 usdPrice)
    private {
        uint256 _weiPrice = IC9EthPriceFeed(_contractPriceFeed).getTokenWeiPrice(usdPrice);
        if (msg.value < 5000000000000000) revert InvalidPaymentAmount(0, msg.value); // fail-safe in case price somehow fails
        if (msg.value != _weiPrice) revert InvalidPaymentAmount(_weiPrice, msg.value);

        (bool success,) = payable(from).call{value: msg.value}("");
        if (!success) revert PaymentFailure(msg.sender, from, msg.value);
    }

    function DOMAIN_SEPARATOR()
    private view
    returns (bytes32) {
        return keccak256(
            abi.encode(
                //keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                nameHash,
                versionHash,
                block.chainid,
                address(this)
            )
        );
    }

    function hashStruct(address from, uint256 tokenId, uint256 price, uint256 expiry)
    public pure
    returns (bytes32) {
        return keccak256(
            abi.encode(LISTING_HASH, from, tokenId, price, expiry)
        );
    }

    /**
     * @dev Recreates the message that was signed on the client 
     * and verifies the signer.
     */
    function _verifySigner(address signer, uint256 tokenId, uint256 price, uint256 expiry, bytes calldata sig)
    private view {
        // 1. Recreate the message
        bytes32 _message = toTypedDataHash(
            DOMAIN_SEPARATOR(),
            hashStruct(signer, tokenId, price, expiry)
        );
        // 2. Recover signer from message
        address _signer = recoverSigner(_message, sig);
        // 3. Verify the signer
        if (_signer != signer) revert InvalidSigner(signer, _signer);
    }

    /*
    function verifySigner(address signer, uint256 tokenId, uint256 price, uint256 expiry, bytes calldata sig)
    public view
    returns (bool) {
        // 1. Recreate the message
        bytes32 _message = toTypedDataHash(
            DOMAIN_SEPARATOR(),
            hashStruct(signer, tokenId, price, expiry)
        );
        // 2. Recover signer from message
        return signer == recoverSigner(_message, sig);
    }
    */

    /**
     * @dev View function to see the contracts this market contract interacts with.
     */
    function getContracts()
    external view
    returns (address priceFeed, address token) {
        priceFeed = _contractPriceFeed;
        token = _contractToken;
    }

    /**
     * @dev View function to see the contracts this market contract interacts with.
     */
    function isPurchaseableFrom(address from, uint256 tokenId)
    public view
    returns (bool) {
        return IC9Token(_contractToken).ownerOf(tokenId) == from;
    }

    function _verifyToken(address from, uint256 tokenId, uint256 listingPrice, uint256 expiry, bytes calldata sig)
    private {
        // 1. Make sure token has not already been purchased
        if (!isPurchaseableFrom(from, tokenId)) {
            revert InvalidListing();
        }
        // 2. Make sure listing is not expired
        if (block.timestamp > expiry) {
            revert ListingExpired();
        }
        // 3. Verify signer has agreed to these parameters
        _verifySigner(from, tokenId, listingPrice, expiry, sig);
        // 4. Emit the purchase event
        emit Purchase(_msgSender(), listingPrice, tokenId);
    }

    /**
     * @dev Purchase a single token and transfer to new owner.
     */
    function purchaseToken(address from, uint256 tokenId, uint256 listingPrice, uint256 expiry, bytes calldata sig)
    external payable
    notFrozen {
        // 1. Verify token and signature and event
        _verifyToken(from, tokenId, listingPrice, expiry, sig);
        // 2. Pay
        _makePayment(from, listingPrice);
        // 3. Transfer
        IC9Token(_contractToken).safeTransferFrom(from, _msgSender(), tokenId);
    }

    /**
     * @dev Processess batch purchase. The token contract has batch transfer 
     * functions that reduce the number of calls and thus gas fees.
     */
    function purchaseTokenBatch(
        address from,
        uint256[] calldata tokenIds,
        uint256[] calldata listingPrices,
        uint256[] calldata expirys,
        bytes[] calldata sigs
    )
    external payable
    notFrozen {
        // 1. Verify signer and get sum price of all tokens in batch
        uint256 _totalListingPrice;
        uint256 _batchSize = tokenIds.length;
        for (uint256 i; i<_batchSize;) {
            // 1. Verify token and signature and event
            _verifyToken(from, tokenIds[i], listingPrices[i], expirys[i], sigs[i]);
            // 2. Accumulate batch price
            unchecked {
                _totalListingPrice += listingPrices[i];
                ++i;
            }
        }
        // 3. Pay
        _makePayment(from, _totalListingPrice);
        // 4. Transfer
        IC9Token(_contractToken).safeTransferBatchFrom(from, _msgSender(), tokenIds);
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractPricer(address pricer)
    external
    onlyOwner {
        if (pricer == _contractPriceFeed) {
            revert AddressAlreadySet();
        }
        _contractPriceFeed = pricer;
    }
}