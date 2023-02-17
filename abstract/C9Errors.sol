// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// C9ERC721
error ApproveToCaller(); //0xb06307db
error BatchSizeTooLarge(uint256 maxSize, uint256 received); //0x01df19f6
error CallerNotOwnerOrApproved(); //0x8c11f105
error InvalidToken(uint256 tokenId); //0x925d6b18
error NonERC721Receiver(); //0x80526d0c
error OwnerAlreadyApproved(); //0x08fb3828
error OwnerIndexOOB(uint256 maxIndex, uint256 received); //0xc643a750
error TokenAlreadyMinted(uint256 tokenId); //0x8b474e54
error TokenEnumIndexOOB(uint256 maxIndex, uint256 received); //0x25601f6d
error TransferFromToSame(); //0x2f2bdfd9
error TransferFromIncorrectOwner(address expected, address received); //0xc0eeaa61
error TransferSizeMismatch(uint256 addressBookSize, uint256 batchSize); //0x9156a5f1
error ZeroAddressInvalid(); //0x14c880ca

// C9OwnerControl
error ActionNotConfirmed(); //0xacdb9fab
error BoolAlreadySet(); //0xf04e4fd9
error ContractFrozen(); //0x4051e961
error NoRoleOnAccount(); //0xb1a60829
error NoTransferPending(); //0x9c6b0866
error C9Unauthorized(); //0xa020ddad
error C9ZeroAddressInvalid(); //0x7c7fa4fb

// Market contract
error InputSizeMismatch(uint256 tokenIdSize, uint256 listingPriceSize, uint256 sigSize); //0x0e8930bf
error InvalidUPrice(string String, uint256 UInt); //0x9dc0c4ff
error InvalidUTokenId(string String, uint256 UInt); //0xa5504564
error InvalidSigner(address expected, address received); //0x7ba5ffb5

// Redeemer
error AddressToFarInProcess(uint256 minStep, uint256 received); //0xb078ecc8
error CancelRemainder(uint256 remainingBatch); //0x2c9f7f1d
error RedeemerBatchSizeTooLarge(uint256 maxSize, uint256 received); //0x66aa3a8c
error SizeMismatch(uint256 maxSize, uint256 received); //0x97ce59d2

// Registrar
error AddressAlreadyRegistered(); //0x2d42c772
error AddressNotInProcess(); //0x286d0071
error CodeMismatch(); //0x179708c0
error SigLengthIncorrect(); //0x4d889d44
error WrongProcessStep(uint256 expected, uint256 received); //0x58f6fd94

// Price Feed
error InvalidPaymentAmount(uint256 expected, uint256 received); //0x05dbe7d3
error PaymentFailure(address from, address to, uint256 value); //0x29292fa2
error PriceFeedDated(uint256 maxDelay, uint256 received); //0xb8875fad

// Token
error AddressAlreadySet(); //0xf62c2d82
error CallerNotContract(); //0xa85366a7
error EditionOverflow(uint256 received); //0x5723b5d1
error IncorrectTokenValidity(uint256 expected, uint256 received); //0xe8c07318
error Input2SizeMismatch(uint256 inputSize1, uint256 inputSize2); //0xa9d63c10
error InvalidVId(uint256 received); //0xcf8cffb0
error NoOwnerSupply(address sender); //0x973d81af
error PeriodTooLong(uint256 maxPeriod, uint256 received); //0xd36b55de
error RoyaltiesAlreadySet(); //0xe258016d
error RoyaltyTooHigh(); //0xc2b03beb
error ValueAlreadySet(); //0x30a4fcdc
error URIAlreadySet(); //0x82ccdaca
error URIMissingEndSlash(); //0x21edfe88
error TokenAlreadyUpgraded(uint256 tokenId); //0xb4aab4a3
error TokenIsDead(uint256 tokenId); //0xf87e5785
error TokenIsLocked(uint256 tokenId); //0xdc8fb341
error TokenNotLocked(uint256 tokenId); //0x5ef77436
error TokenNotUpgraded(uint256 tokenId); //0x14388074
error TokenPreRedeemable(uint256 tokenId); //0x04df46e6
error Unauthorized(); //0x82b42900
error ZeroEdition(); //0x2c0dcd39
error ZeroMintId(); //0x1ed046c6
error ZeroValue(); //0x7c946ed7
error ZeroTokenId(); //0x1fed7fc5

// C9Game
error ExpiredToken(uint256 minTokenId, uint256 receivedTokenId); //0x3f25aa3c
error GameSizeError(uint256 received); //0x93ebcd38
error InvalidIndices(); //0x2cd4dad3
error NotAWinner(uint256 tokenId); //0x3b9052cf

