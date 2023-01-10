// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./interfaces/IC9Token.sol";
import "./utils/Helpers.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

address constant MINTER_ADDRESS = 0x4f06EC058c9844750cD8B61b913BFa75AF9c565C;

contract C9Market is C9OwnerControl {

    address private contractPricer;
    address private immutable contractToken;

    constructor(address _contractToken) {
        contractToken = _contractToken;
        _frozen = true;
    }

    event Purchase(
        address indexed buyer,
        uint256 indexed price,
        uint256 indexed tokenId
    );

    event PurchaseBatch(
        address indexed buyer,
        uint256 indexed price,
        uint256[] indexed tokenId
    );

    // Builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash)
        internal pure
        returns (bytes32) {
            return keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    hash
                )
            );
    }

    function _checkSigner(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        private pure {
            // This recreates the message that was signed on the client.
            bytes32 hash = keccak256(bytes(string.concat(_tokenId, _listingPrice)));
            bytes32 message = prefixed(hash);
            // Recover signer from message
            address signer = recoverSigner(message, sig);
            if (signer != MINTER_ADDRESS) {
                revert InvalidSigner(MINTER_ADDRESS, signer);
            }
    }

    function _checkPayment(uint256 _usdPrice)
        private {
            // Check to make sure msg.value matches wei listing price
            uint256 _weiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_usdPrice);
            if (msg.value != _weiPrice) {
                revert InvalidPaymentAmount(_weiPrice, msg.value);
            }
            // Check to ensure payment was received
            (bool success,) = payable(MINTER_ADDRESS).call{value: msg.value}("");
            if(!success) {
                revert PaymentFailure(msg.sender, MINTER_ADDRESS, msg.value);
            }
    }

    function _verifyListing(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        private pure
        returns (uint256, uint256) {
            _checkSigner(_tokenId, _listingPrice, sig);
            // Convert string to Unit and check conversion is good
            (uint256 _uListingPrice, bool _validPrice) = Helpers.strToUint(_listingPrice);
            if (!_validPrice) {
                revert InvalidUPrice(_listingPrice, _uListingPrice);
            }
            // Convert string to Unit and check conversion is good
            (uint256 _uTokenId, bool _validTokenId) = Helpers.strToUint(_tokenId);
            if (!_validTokenId) {
                revert InvalidUTokenId(_tokenId, _uTokenId);
            }
            return (_uTokenId, _uListingPrice);
        }

    function purchaseToken(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        external payable
        notFrozen() {
            (uint256 _uTokenId, uint256 _uListingPrice) = _verifyListing(_tokenId, _listingPrice, sig);
            _checkPayment(_uListingPrice);
            IC9Token(contractToken).safeTransferFrom(MINTER_ADDRESS, msg.sender, _uTokenId);
            emit Purchase(msg.sender, _uListingPrice, _uTokenId);
    }

    function purchaseTokenBatch(
        string[] calldata _tokenId,
        string[] calldata _listingPrice,
        bytes[] calldata sig
        )
        external payable
        notFrozen() {
            uint256 _batchSize = _tokenId.length;
            if (_batchSize != _listingPrice.length || _batchSize != sig.length) {
                revert InputSizeMismatch(_batchSize, _listingPrice.length, sig.length);
            }
            // Verify and get sum of all tokens in batch
            uint256 _totalUSDPrice;
            uint256 _uListingPrice;
            uint256[] memory _uTokenId = new uint256[](_batchSize); 
            for (uint256 i; i<_batchSize;) {
                (_uTokenId[i], _uListingPrice) = _verifyListing(_tokenId[i], _listingPrice[i], sig[i]);
                _totalUSDPrice += _uListingPrice;
                emit Purchase(msg.sender, _uTokenId[i], _uListingPrice);
                unchecked {++i;}
            }
            // Check payment and emit batch purchase if needed to check against individual events
            _checkPayment(_totalUSDPrice);
            IC9Token(contractToken).safeTransferFrom(MINTER_ADDRESS, msg.sender, _uTokenId);
            emit PurchaseBatch(msg.sender, _totalUSDPrice, _uTokenId);
    }

    function recoverSigner(bytes32 message, bytes calldata sig)
        private pure
        returns (address) {
            (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);
            return ecrecover(message, v, r, s);
    }

    // https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
    function splitSignature(bytes memory sig)
        internal pure
        returns (bytes32 r, bytes32 s, uint8 v) {
            if (sig.length != 65) {
                revert("Sig length incorrect");
            }
            assembly {
                // first 32 bytes, after the length prefix
                r := mload(add(sig, 32))
                // second 32 bytes
                s := mload(add(sig, 64))
                // final byte (first byte of the next 32 bytes)
                v := byte(0, mload(add(sig, 96)))
            }
    }


}