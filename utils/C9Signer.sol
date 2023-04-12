// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

abstract contract C9Signer {
    /**
     * @dev Builds a prefixed hash to mimic the behavior of personal_sign.
     */
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

    /**
     * @dev
     * https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
     */
    function recoverSigner(bytes32 message, bytes calldata sig)
    internal pure
    returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);
        return ecrecover(message, v, r, s);
    }

    /**
     * @dev
     * https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/
     */
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
