// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

error ApproveToCaller(); //0xb06307db
error BatchSizeTooLarge(uint256 maxSize, uint256 received); //0x01df19f6
error CallerNotOwnerOrApproved(); //0x8c11f105
error InvalidToken(uint256 tokenId); //0x925d6b18
error NonERC721Receiver(); //0x80526d0c
error OwnerAlreadyApproved(); //0x08fb3828
error OwnerIndexOOB(uint256 maxIndex, uint256 received); //0xc643a750
error SplitTransferSizeMismatch(uint256 addressBookSize, uint256 batchSize);
error TokenAlreadyMinted(uint256 tokenId); //0x8b474e54
error TokenEnumIndexOOB(uint256 maxIndex, uint256 received); //0x25601f6d
error TransferFromToSame(); //0x2f2bdfd9
error TransferFromIncorrectOwner(address expected, address received); //0xc0eeaa61
error ZeroAddressInvalid(); //0x14c880ca

interface IERC721opt {
    function safeTransferFromBatch(address from, address to, uint256[] calldata _tokenId) external;
    function splitTransferFrom(address from, address[] calldata to, uint256[] calldata _tokenId) external;
    function transferFromBatch(address from, address to, uint256[] calldata _tokenId) external;
}