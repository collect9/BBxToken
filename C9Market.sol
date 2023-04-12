// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./interfaces/IC9Token.sol";
import "./utils/C9Context.sol";
import "./utils/C9Signer.sol";
import "./utils/Helpers.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

address constant MINTER_ADDRESS = 0x4f06EC058c9844750cD8B61b913BFa75AF9c565C;

contract C9Market is C9Context, C9Signer, C9OwnerControl {

    address private contractPriceFeed;
    address private immutable contractToken;
    address public signer;

    event Purchase(
        address indexed buyer,
        uint256 indexed price,
        uint256 indexed tokenId
    );

    constructor(address _contractPriceFeed, address _contractToken) {
        contractPriceFeed = _contractPriceFeed;
        contractToken = _contractToken;
        signer = MINTER_ADDRESS;
    }

    /**
     * @dev Checks to make sure payment amount is correct and payment 
     * transfer is successful.
     */
    function _checkPayment(uint256 usdPrice)
    private {
        // Check to make sure msg.value matches wei listing price
        uint256 _weiPrice = IC9EthPriceFeed(contractPriceFeed).getTokenWeiPrice(usdPrice);
        if (msg.value != _weiPrice) {
            revert InvalidPaymentAmount(_weiPrice, msg.value);
        }
        // Check to ensure payment was received
        (bool success,) = payable(MINTER_ADDRESS).call{value: msg.value}("");
        if(!success) {
            revert PaymentFailure(msg.sender, MINTER_ADDRESS, msg.value);
        }
    }

    /**
     * @dev Recreates the message that was signed on the client 
     * and verifies the signer.
     */
    function _verifySigner(string calldata tokenId, string calldata listingPrice, bytes calldata sig)
    private view {
        // 1. Get the hash
        bytes32 _hash = keccak256(
            bytes(
                string.concat(tokenId, listingPrice)
            )
        );
        // 2. Recreate the message
        bytes32 _message = prefixed(_hash);
        // 3. Recover signer from message
        address _signer = recoverSigner(_message, sig);
        // 4. Verify the signer
        if (_signer != signer) revert InvalidSigner(signer, _signer);
    }

    /**
     * @dev Converts string to uint. It does a conversion back to double-check 
     * the conversion is correct (may not be necessary).
     */
    function _strToUInt(string calldata input)
    private pure
    returns (uint256) {
        // 1. First try to convert to unsigned
        (uint256 _unsignedInput, bool _valid) = Helpers.strToUint(input);
        if (!_valid) {
            revert InvalidUPrice(input, _unsignedInput);
        }
        // 2. Convert back to bytes
        bytes32 bInput = Helpers.uintToBytes(_unsignedInput);
        // 3. Check for match
        if (bytes32(bytes(input)) != bInput) {
            revert StringConversionError();
        }
        return _unsignedInput;
    }

    /**
     * @dev View function to see the contracts this market contract interacts with.
     */
    function getContracts()
    external view
    returns (address priceFeed, address token) {
        priceFeed = contractPriceFeed;
        token = contractToken;
    }

    /**
     * @dev View function to see the contracts this market contract interacts with.
     */
    function isPurchaseable(uint256 tokenId)
    public view
    returns (bool) {
        return IC9Token(contractToken).ownerOf(tokenId) == MINTER_ADDRESS;
    }

    /**
     * @dev Purchase a single token and transfer to new owner.
     */
    function purchaseToken(string calldata tokenId, string calldata listingPrice, bytes calldata sig)
    external payable
    notFrozen() {
        // 1. Verify signer
        _verifySigner(tokenId, listingPrice, sig);
        // 2. Convert strings to unsigned for payment
        uint256 _uListingPrice = _strToUInt(listingPrice);
        _checkPayment(_uListingPrice);
        // 3. Convert strings for tokenId
        uint256 _uTokenId = _strToUInt(tokenId);
        // 4. Make sure this tokenId has not already been purchased
        if (!isPurchaseable(_uTokenId)) {
            revert InvalidToken(_uTokenId);
        }
        // 4. Transfer and emit event
        IC9Token(contractToken).safeTransferFrom(MINTER_ADDRESS, _msgSender(), _uTokenId);
        emit Purchase(_msgSender(), _uListingPrice, _uTokenId);
    }

    /**
     * @dev Processess batch purchase. The token contract has batch transfer 
     * functions that reduce the number of calls and thus gas fees.
     */
    function purchaseTokenBatch(
        string[] calldata tokenIds,
        string[] calldata listingPrices,
        bytes[] calldata sigs
    )
    external payable
    notFrozen() {
        // 1. Check the input sizes match
        uint256 _batchSize = tokenIds.length;
        if (_batchSize != listingPrices.length || _batchSize != sigs.length) {
            revert InputSizeMismatch(_batchSize, listingPrices.length, sigs.length);
        }
        // 2. Verify signer and get sum price of all tokens in batch
        uint256 _uTokenId;
        uint256 _uListingPrice;
        uint256 _totalListingPrice;
        uint256[] memory _uTokenIds = new uint256[](_batchSize); 
        for (uint256 i; i<_batchSize;) {
            _verifySigner(tokenIds[i], listingPrices[i], sigs[i]);
            _uTokenId = _strToUInt(tokenIds[i]);
            if (!isPurchaseable(_uTokenId)) {
                revert InvalidToken(_uTokenId);
            }
            _uTokenIds[i] = _uTokenId;
            _uListingPrice = _strToUInt(listingPrices[i]);
            emit Purchase(_msgSender(), _uTokenId, _uListingPrice);
             unchecked {
                _totalListingPrice += _uListingPrice;
                ++i;
            }
        }
        // 3. Check payment
        _checkPayment(_totalListingPrice);
        // 4. Transfer
        IC9Token(contractToken).safeTransferBatchFrom(MINTER_ADDRESS, _msgSender(), _uTokenIds);
    }

    /**
     * @dev Sets/updates the pricer contract 
     * address if ever needed.
     */
    function setContractPricer(address _address)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (contractPriceFeed == _address) {
            revert AddressAlreadySet();
        }
        contractPriceFeed = _address;
    }

    /**
     * @dev Sets the signer. This is an easy but hackish way to
     * 'expire' signatures from the current signer. New
     * signatures will need to be created from the 
     * new signer.
     */
    function setSigner(address _address)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        if (signer == _address) {
            revert AddressAlreadySet();
        }
        signer = _address;
    } 
}