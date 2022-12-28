// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./utils/interfaces/IC9ERC721.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

address constant MINTER_ADDRESS = 0x8B525b744C73e46dB14d0E1ACD8842b3071ff63e;

contract C9Market is C9OwnerControl {

    uint96 private _saleFraction = 100;
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

    function _checkSigner(uint256 _tokenId, uint256 _listingPrice, bytes calldata sig)
        private pure {
        // This recreates the message that was signed on the client.
        bytes32 hash = keccak256(
            abi.encodePacked(
                _tokenId,
                _listingPrice
            )
        );
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
                revert PaymentFailure();
            }
    }

    function purchaseToken(uint256 _tokenId, uint256 _listingPrice, bytes calldata sig)
        external payable
        notFrozen() {
            _checkSigner(_tokenId, _listingPrice, sig);
            uint256 _totalUSDPrice = _listingPrice;
            if (_saleFraction < 100) {
                _totalUSDPrice = _totalUSDPrice * _saleFraction / 100;
            }
            _checkPayment(_totalUSDPrice);
            IC9ERC721(contractToken).safeTransferFrom(MINTER_ADDRESS, msg.sender, _tokenId);
            emit Purchase(msg.sender, _totalUSDPrice, _tokenId);
    }

    function purchaseTokenBatch(
        uint256[] calldata _tokenId,
        uint256[] calldata _listingPrice,
        bytes[] calldata sig
        )
        external payable
        notFrozen() {
            uint256 _batchSize = _tokenId.length;
            if (_batchSize != _listingPrice.length || _batchSize != sig.length) {
                revert InputSizeMismatch(_batchSize, _listingPrice.length, sig.length);
            }

            uint256 _totalUSDPrice;
            for (uint256 i; i<_batchSize;) {
                _checkSigner(_tokenId[i], _listingPrice[i], sig[i]);
                _totalUSDPrice += _listingPrice[i];
                emit Purchase(msg.sender, _tokenId[i], _listingPrice[i]);
                unchecked {++i;}
            }

            if (_saleFraction < 100) {
                _totalUSDPrice = _totalUSDPrice * _saleFraction / 100;
            }

            _checkPayment(_totalUSDPrice);

            IC9ERC721(contractToken).safeTransferFromBatch(MINTER_ADDRESS, msg.sender, _tokenId);
            emit PurchaseBatch(msg.sender, _totalUSDPrice, _tokenId);
    }

    function recoverSigner(bytes32 message, bytes calldata sig)
        private pure
        returns (address) {
            uint8 v;
            bytes32 r;
            bytes32 s;
            (v, r, s) = splitSignature(sig);
            return ecrecover(message, v, r, s);
    }

    // https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
    function splitSignature(bytes memory sig)
        internal pure
        returns (uint8, bytes32, bytes32) {
            require(sig.length == 65);

            bytes32 r;
            bytes32 s;
            uint8 v;

            assembly {
                // first 32 bytes, after the length prefix
                r := mload(add(sig, 32))
                // second 32 bytes
                s := mload(add(sig, 64))
                // final byte (first byte of the next 32 bytes)
                v := byte(0, mload(add(sig, 96)))
            }

            return (v, r, s);
    }

    /**
     * Sets the min listing floor price.
     */
    function setSaleFraction(uint256 _newSaleFraction)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_newSaleFraction == _saleFraction) {
                revert ValueAlreadySet();
            }
            if (_saleFraction > 100 || _saleFraction < 30) {
                revert InvalidSaleFraction(_newSaleFraction);
            } 
            _saleFraction = uint96(_newSaleFraction);
    }

}