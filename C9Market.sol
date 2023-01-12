// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./interfaces/IC9Token.sol";
import "./utils/Helpers.sol";
import "./utils/interfaces/IC9EthPriceFeed.sol";

address constant MINTER_ADDRESS = 0x4f06EC058c9844750cD8B61b913BFa75AF9c565C;

contract C9Market is C9OwnerControl {

    address private contractPriceFeed;
    address private immutable contractToken;
    address public _signer = MINTER_ADDRESS;

    // goerli: 0x7c0d06c44832e28ba5b2b8cc8a2d6603c8631d16
    constructor(address _contractPriceFeed, address _contractToken) {
        contractPriceFeed = _contractPriceFeed;
        contractToken = _contractToken;
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

    /**
     * @dev Checks to make sure payment amount is correct and payment 
     * transfer is successful.
     */
    function _checkPayment(uint256 _usdPrice)
        private {
            // Check to make sure msg.value matches wei listing price
            uint256 _weiPrice = IC9EthPriceFeed(contractPriceFeed).getTokenWeiPrice(_usdPrice);
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
     * @dev Verifies the signer.
     */
    function _checkSigner(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        private view {
            // This recreates the message that was signed on the client.
            bytes32 hash = keccak256(bytes(string.concat(_tokenId, _listingPrice)));
            bytes32 message = prefixed(hash);
            // Recover signer from message
            address signer = recoverSigner(message, sig);
            // Verify signer
            if (signer != _signer) {
                revert InvalidSigner(_signer, signer);
            }
    }

    /**
     * @dev Verifies the listing data by checking the signer is valid, and 
     * also makes sure the string representation of numbers properly convert to uint.
     */
    function _verify(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        private view
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
     * @dev Builds a prefixed hash to mimic the behavior of personal_sign.
     */
    function prefixed(bytes32 hash)
        private pure
        returns (bytes32) {
            return keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    hash
                )
            );
    }

    /**
     * @dev Purchase a single token and transfer to new owner.
     */
    function purchaseToken(string calldata _tokenId, string calldata _listingPrice, bytes calldata sig)
        external payable
        notFrozen() {
            (uint256 _uTokenId, uint256 _uListingPrice) = _verify(_tokenId, _listingPrice, sig);
            _checkPayment(_uListingPrice);
            IC9Token(contractToken).safeTransferFrom(MINTER_ADDRESS, msg.sender, _uTokenId);
            emit Purchase(msg.sender, _uListingPrice, _uTokenId);
    }

    /**
     * @dev Processess batch purchase. The token contract has batch transfer 
     * functions that reduce the number of calls and thus gas fees.
     */
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
            // Verify and get sum price of all tokens in batch
            uint256 _totalUSDPrice;
            uint256 _uListingPrice;
            uint256[] memory _uTokenId = new uint256[](_batchSize); 
            for (uint256 i; i<_batchSize;) {
                (_uTokenId[i], _uListingPrice) = _verify(_tokenId[i], _listingPrice[i], sig[i]);
                emit Purchase(msg.sender, _uTokenId[i], _uListingPrice);
                unchecked {
                    _totalUSDPrice += _uListingPrice;
                    ++i;
                }
            }
            // Check payment and emit batch purchase (if needed to check against individual purchase events)
            _checkPayment(_totalUSDPrice);
            IC9Token(contractToken).safeTransferFrom(MINTER_ADDRESS, msg.sender, _uTokenId);
            emit PurchaseBatch(msg.sender, _totalUSDPrice, _uTokenId);
    }

    /**
     * @dev
     * https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
     */
    function recoverSigner(bytes32 message, bytes calldata sig)
        private pure
        returns (address) {
            (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);
            return ecrecover(message, v, r, s);
    }

    /**
     * @dev
     * https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
     */
    function splitSignature(bytes memory sig)
        private pure
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
     * @dev Sets the signer. This is an easy way to
     * expire signatures from the current signer. New
     * signatures will need to be created from the 
     * new signer.
     */
    function setSigner(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_signer == _address) {
                revert AddressAlreadySet();
            }
            _signer = _address;
    } 
}