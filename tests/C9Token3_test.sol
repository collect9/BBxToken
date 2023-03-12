// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.4.22 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";

import "../C9Token3.sol";
import "../abstract/C9Struct4.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract testSuite is C9Struct {

    address c9tOwner;

    // Variables to save and check against
    mapping(address => uint256) balances;
    mapping(address => uint256) redemptions;
    mapping(address => uint256) transfers;
    mapping(address => uint256) votes;

    uint256 _timestamp;

    // Raw data stored to compare tests against
    TokenData[32] _rawData;

    // Create contract and mint some NFTs
    C9Token c9t;
    function beforeAll() public {

        // Store raw data input to compare against
        _rawData[0] = TokenData(0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 350, 0, 78081, 0, 0, 2500, 10, "CUBBIE=dB1B2C2B3C3G3d84G4A6B6C7B8d19d49G98AGAd1Bd4BGB3C2D6Dd7DFD1Ed2Ed5E1Fd2F9FdAFDF2GGGg3:S:9:3b:B:3:E:g4:R:A:f25:C:f25:G=293234434674g6:C:Ic:Jc:K:25:27:Lc:Nc:Z:O:g9:Y");
        _rawData[1] = TokenData(0, 0, 0, 0, 0, 6, 1, 3, 1, 0, 1, 5, 0, 375, 0, 893607, 0, 0, 1800, 3, "ROYAL BLUE PEANUT=D1B2C2d93C3G384G4C5dA6C7B819j2969G9d7AGA1Bj2B6BGB1C2CACd1Dj4DADBDBE2F3Fd7FdCFd4Gj7GDGdEGg3:3b:9:3h:A:3b:B:f33:C:g8:a:E=2932345254768196g6:Cc:J:20:23c:Kc:L:M:34c:41c:43c:49:g9:Eb:W:21h:K:Nh");
        _rawData[2] = TokenData(0, 0, 0, 0, 0, 6, 0, 3, 1, 0, 0, 5, 0, 475, 0, 78844, 0, 0, 300, 2, "VALENTINO=D1C2B3C3G3d84G4dA6C7B889G92Ad9AjDA8Bd9BCBGBd1C9CAC9DADFD7EBE2F3F7F8FCFDFd2Gj7GGGg3:f33:A:b:B:f67:C:g4:c:9:1:D:c:E=29384143546274g6:C:G:H:23c:M:Z:O:g9:Gh:Y");
        _rawData[3] = TokenData(0, 0, 0, 0, 0, 4, 4, 3, 1, 4, 1, 2, 0, 375, 0, 75129, 0, 0, 1500, 7, "NANA=dB1B2B3C3G3d84G4C5C7B849j89G92A3A8A9AGAd1Bd7BBBCBGB4C5CACFDCE8Fj9FDF2Gj3G7GGGg3:3b:6:3h:A:1:D:3:D:1:F:g8:a:E=293952546174g6:C:G:K:L:M:Z:O:g9:Bh:Eb:Y");
        _rawData[4] = TokenData(0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 3, 1, 0, 325, 0, 75909, 0, 0, 5000, 12, "DIGGER 4C=dB1B2B3C3G3d84G4C7B819B9G92A3AjDAd2Bd5BBBCBGBd1Cj4C3Dd4D7DBDFD1E6ECE1F2FCFDF1G5Gd6GAGGGg3:3b:6:3:A:g5:.8:9:g6:.83:F=294147506174g6:C:J:X:27:Z:O:g9:Ah:J:Y");
        _rawData[5] = TokenData(0, 0, 0, 0, 0, 6, 4, 1, 1, 1, 0, 4, 0, 400, 0, 74724, 0, 0, 1400, 3, "PATTI DF=D1C2B3C3G3d84G4C5C7B8d19j49G95A6AdAAjDAd6BBBCBGB1C5Cj6Cd1Dd6DFDd4ECEj3FCFDF1G7G8GGGg3:3b:6:3b:9:S:F:1:G=293247546374g6:C:20:25:Lc:Z:O:g9:C:Eb:Y");
        _rawData[6] = TokenData(0, 0, 0, 0, 0, 2, 4, 2, 1, 5, 0, 3, 0, 375, 0, 893757, 0, 0, 1500, 4, "TEDDY OF BROWN=dB1C2d93C3G384G4B5C5dA6C7B8d1959G9GA1Bd9BCBGB2Cj3Cj7Cd9D2E3EAEBE1F2FdCFd6GjAGdEGg3:3b:9:1:D:g4:.75:A:R:A:1:B:f25:E=293234495254808396g6:Cc:J:20:X:L:M:34c:O:43c:49:g9:W:21h:K:Nh");
        _rawData[7] = TokenData(0, 0, 0, 0, 0, 5, 0, 2, 1, 3, 2, 2, 0, 375, 0, 75512, 0, 0, 2000, 8, "TEDDY BROWN=C1D1B2C2B3C3G3d84G4B5C7B819A9B9G91Aj9AjDAGB6Dj7DBDFDd7ECE9FdAFDF7Gd8GGGg3:3b:6:f67:9:f67:A:b:B:f67:B:h:C:f33:F:g4:2a:B:f75:C:a:D:g5:.2:E=2936436374g6:C:20:22c:27:Z:O:g9:Ah:Gb:J:Y");
        _rawData[8] = TokenData(0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 4, 0, 375, 0, 893857, 0, 0, 1500, 3, "TEDDY OF TEAL=dB1C2d93C3G384G4A6B6C7B819d99C9G92AGA2B3Bj8BCBGB6Dj3E3FdCFjAGdEGg3:f67:9:3h:A:b:D:3:D:3:E:2:F:b:G:g4:1:A:a:C:g5:f2:C=293234435254798396g6:Cc:J:20:23:K:L:M:34c:O:43c:49:g9:W:21h:K:Nh");
        _rawData[9] = TokenData(0, 0, 0, 0, 0, 5, 4, 1, 1, 1, 0, 4, 0, 375, 0, 74726, 0, 0, 1800, 3, "SPLASH=E1j82dC2d83jB3D4A5B5G58687D7E7d48E8j1959E9j6ACA1Bd6B2Cd3Cd6C3D4DADEEDFdEFd7GjAGg3:3b:6:3:9:b:A:g4:3:D:a:G:g5:.4:E:f6:E:g8:.38:F=293248606274g6:C:20:25c:27:Z:O:g9:C:Eb:Y");
        _rawData[10] = TokenData(0, 0, 0, 0, 0, 5, 1, 3, 1, 4, 1, 3, 0, 350, 0, 72467, 0, 0, 2800, 6, "ROYAL BLUE PEANUT=C2B3C3G3d84G4C5dA6C7B869j79G94A5AdAAjDA1BBBCBGB2CACj3Dd7DjCD1Ed2EBECEd1F5F6FCFDFj1GGGg3:3h:1:h:9:2:B:2:E:S:F:g4:1:C=293643486374g6:C:Jc:25:27:Z:O:g9:Ah:J:Y");
        _rawData[11] = TokenData(0, 0, 0, 0, 0, 2, 4, 2, 1, 0, 0, 4, 0, 450, 0, 69358, 0, 0, 500, 3, "ALLY=D1B2B3C3G3d84G4B5dA6C7B8d19d4989G92A3A7AGA2Bd3B7Bj8BCBGB3C2Dd7DBDFDj8E2FCFDFj1GjDGg3:3b:9:S:C:b:E:g4:R:A:f5:F:f5:G=283234526374g6:C:J:20:23c:N:Z:O:g9:Eb:I:Y");
        _rawData[12] = TokenData(0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 475, 0, 69272, 0, 0, 350, 2, "PATTI=C1D1B2C2B3C3G3d84G4B5C5dA6C7B8d29j59j99G9d5AGAd1Bj4BGB1C9C1D6DADBDFDd3FdAFDF1Gd2G6Gd7GjDGg3:3h:A:b:E:g4:2a:B:2:E=28323443525474g6:C:I:J:23:N:31:Z:O:g9:Ih:Y");
        _rawData[13] = TokenData(0, 0, 0, 0, 0, 2, 4, 2, 1, 5, 0, 5, 0, 425, 0, 76907, 0, 0, 750, 2, "TEDDY OF TEAL=C2B3C3G3d84G4C7B81979B9G91A2Ad6AAAdBAGAj1Bj5Bd9BCBGB2CAC1Dd2D5DdADFDCEd1F9FdAFDF5Gd6GGGg3:3h:1:3b:6:1:9:f67:F:b:G:g4:f25:C:g7:.29:E=2932384351545774g6:C:H:23:Mc:Z:O:g9:Y");
        _rawData[14] = TokenData(0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 475, 0, 67685, 0, 0, 350, 2, "HAPPY=dB1C2B3C3G3d84G4A6B6C7B8d19d4979C9G91A2Aj6ACAjDA4B5BGB1C5C9CAC3DBDjCDj2Ej6ECEd1F6Fd7FdAFDFd6GjDGg3:3b:B:2:D:g4:a:G=2836384352545774g6:C:G:23:K:N:Z:O:g9:Y");
        _rawData[15] = TokenData(0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 350, 0, 78082, 0, 0, 3000, 10, "SQUEALER=C1D1B2C2B3C3G3d84G4A6B6C7B83999A9G95Aj6AGA1Bd2B6BBBCBGBd2C5C8DFDd9E1Fd2F5Fj9FDFGGg3:b:A:3h:A:S:C:b:D:h:G:g5:.2:E:f2:G=2932344346545774g6:C:Ic:Jc:Kc:25c:N:Z:O:g9:Y");
        _rawData[16] = TokenData(0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 4, 0, 400, 0, 78466, 0, 0, 1400, 3, "WEB=C1D1C2B3C3G3d84G4C5dA6C7B81929A9G92A3ACAjDAGB3C4Cd8C2Dj7DFD5E6EBE2Fd3F8Fj9FDF1Gd2Gd7GGGg3:f33:9:3b:B:g4:f25:A:g5:.4:B=2932404346545774g6:C:Hc:Ic:25c:31:Z:O:g9:Y");
        _rawData[17] = TokenData(0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 475, 0, 54985, 0, 0, 350, 2, "INKY NM=dB1C2B3C3G3d84G4A6B6C7B8j19G97Aj8AjDAd1B5Bd6Bd9BCBGB1Cd2C5C1D2D7D8DFD2E3Ed7ECEd2FCFDFd1GdEGg3:3:9:S:G:g4:a:A:g5:f2:F=253543526174g6:E:G:23:K:27:Z:O:g9:D:J:Y");
        _rawData[18] = TokenData(0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 4, 0, 375, 0, 893853, 0, 0, 1500, 3, "TEDDY OF JADE=dB1C2B3C3G384G4A6B6C7B8d39d99C9G9GAj2B6BGBACd2Dd5Dj8D1Ej2E7Ej8Ed1F7Fd8FdCF3Gj7GDGdEGg3:h:A:3h:A:3b:B:g4:f5:A:.75:C=293234435254698096g6:Cc:J:20:23:K:L:M:Z:O:43c:49:g9:W:23h:27b:Nh");
        _rawData[19] = TokenData(0, 0, 0, 0, 0, 5, 4, 1, 1, 1, 0, 3, 0, 375, 0, 78858, 0, 0, 1750, 4, "PATTI DF=D1B2B3C3G3d84G4B5dA6C7B819A9G91AdBAGA1Bd2B6B7BGB1C2CAC7DFD6EdAFDFd8GGGg3:3b:B:h:D:b:E:3:E:b:G:g4:1:9:g5:.8:C:.8:F:g6:c:A=293841525974g6:C:G:H:23c:27:Z:O:g9:Eb:W:Y");
        _rawData[20] = TokenData(0, 0, 0, 0, 0, 2, 1, 3, 1, 4, 0, 4, 0, 475, 0, 71498, 0, 0, 300, 3, "SQUEALER=D1B2B3C3G3d84G4B5A6B6C7B819A9G9j2A9AdAAjDA2BBBCBGBd1C6Cd8DBDFD2Ej3Ej8ECE2Fd3Fj6FdAFDF6G7GGGg3:2:B:S:C:b:D:g4:a:G:g5:.8:9=293248526274g6:C:Hc:X:22c:27:Z:O:g9:D:Jb:Y");
        _rawData[21] = TokenData(0, 0, 0, 0, 0, 5, 0, 2, 1, 2, 2, 2, 0, 375, 0, 73523, 0, 0, 2000, 8, "CHILLY=B2C2B3C3G3d84G4C5C7B83979d89B9G91Ad8ACAjDAj3BGBd3Cd6Cj1DFD1E2E8Ed9ECE4Fd5F9FdAFDF7Gd8GGGg3:3h:1:3b:6:1:A:3b:B:2:D:3b:D:h:G=2932365474g6:C:20:23c:N:Z:O:g9:Eb:Gh:Ih:Y");
        _rawData[22] = TokenData(0, 0, 0, 0, 0, 6, 0, 2, 1, 3, 2, 2, 0, 375, 0, 73017, 0, 0, 2000, 8, "QUACKERS=C2B3C3G3d84G4B5C7B8G9GAd1BBBCBGB1Cj2C2D3DBDjCD1Ed2E7EBECEd6Fj9FDFd5G9GAGGGg3:3h:1:3b:6:2b:9:b:G:g4:R:A:f25:B:f25:D:a:F=29435474g6:C:G:Hc:J:25c:31:Z:O:g9:Fb:J:Y");
        _rawData[23] = TokenData(0, 0, 0, 0, 0, 6, 0, 2, 1, 3, 2, 2, 0, 375, 0, 67397, 0, 0, 2000, 8, "CHOCOLATE=C2B3C3G3d84G4B5A6B6C7B8d29d99C9G9d1AGA5Bd6Bd9BCBGB3Cd4C9CAC1D5DFDd5E8ECE6FCFDFj5G9GjDGg3:3h:1:f67:A:3h:A:b:B:b:E:b:F:b:G:g4:2a:D=2832404850545674g6:C:Ic:X:22c:N:Z:O:g9:Y");
        _rawData[24] = TokenData(0, 0, 0, 0, 0, 2, 1, 3, 1, 4, 0, 4, 0, 450, 0, 70772, 0, 0, 500, 3, "NIP OF=C1D1B2C2B3C3G3d84G4B5C5dA6C7B819G99AdAAjDABBCBGB7C8C1Dd2Dj5DADFDd5E8Ed6Fj9FDF6G7GGGg3:f67:A:h:C:b:E:3b:E:g4:.75:B:a:F:a:G:g5:f6:9=2932404352545674g6:C:Hc:23:N:Z:O:g9:Y");
        _rawData[25] = TokenData(0, 0, 0, 0, 0, 2, 1, 3, 1, 4, 0, 3, 0, 450, 0, 895892, 0, 0, 600, 4, "TUSK=dB1B2B3C3G384G4A6B6C7B8d1949A9B9G91Ad2A6Aj7ACAjDA3BBBCBGB2C7Cj7DBD2E3E1Fd2F6F7FdCFDGdEGg3:2b:B:S:G:g5:.2:D:g6:1:E=293239547496g6:Cc:H:I:X:23:Kc:25c:L:M:Z:O:39c:41:43c:49:g9:W:23:Nh");
        _rawData[26] = TokenData(0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 350, 0, 78079, 0, 0, 2500, 10, "SPOT=dB1B2B3C3G3d84G4B5C5dA6C7B8d79G9d3A8AGA1Bd2B7BGBj7C1Dj5DFDd1FCFDFj5GAGGGg3:3h:A:b:C:f33:E:f67:F:b:G:g4:2a:B:2:E:g5:.2:9=2932344352596174g6:C:Ic:Jc:23c:Kc:27:L:Z:O:g9:Y");
        _rawData[27] = TokenData(0, 0, 0, 0, 0, 6, 4, 1, 1, 1, 0, 4, 0, 375, 0, 894296, 0, 0, 1500, 3, "FLASH=dB1B2d93C3G384G4C5C7B899G9j2Ad8ACAjDA1B5BBBCBGBj1Cj5CAC2DADBD1EAEBE2FdCFjAGdEGg3:3b:6:b:9:2b:B:2:F:g5:.8:D:.8:E:.8:G=293236525473768596g6:Cc:J:20:K:L:M:Z:40c:43c:49:g9:Eb:W:23:Nh");
        _rawData[28] = TokenData(0, 0, 0, 0, 0, 6, 1, 3, 1, 0, 0, 6, 0, 475, 0, 895888, 0, 0, 450, 1, "TEDDY TEAL=D1B2G3d84G4A6B6C7B82969G93A4ACAjDA1Bj6BBBCBGBj2Cd8C1D1Fd2F7FdCF7GDGdEGg3:3b:3:3:9:1:D:3:D:b:E:1:G:g5:f2:A:g7:.71:E=293239495254698396g6:Cc:H:I:X:22c:L:M:36:40:43c:49:g9:W:21h:25b:Nh");
        _rawData[29] = TokenData(0, 0, 0, 0, 0, 6, 1, 3, 1, 0, 0, 6, 0, 500, 0, 66365, 0, 0, 125, 1, "BLACKIE=dB1C2B3C3G3d84G4C5dA6C7B879G92Ad3Ad7AGAj8BCBGBj1C5Cj9DFD1Ed2E5EdAE5Fj6FCFDF8G9GjDGg3:3b:9:3h:A:2b:C:f67:D:b:F:g5:.2:B:g6:.17:G=28323443465874g6:C:Ic:K:27:Z:O:g9:W:Y");
        _rawData[30] = TokenData(0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 475, 0, 77003, 0, 0, 300, 2, "GOLDIE=B2C2B3C3G3d84G4C7B8d2979G96AGABBCBGB1C2C9C7DBDjCD7Ed8ECEj3Fd7FdAFDF3Gj4G9GAGGGg3:3h:1:3b:6:b:B:g4:a:A:1:C:c:D:c:E:g5:f8:A=29324043465874g6:C:H:Kc:31:Z:O:g9:I:Y");
        _rawData[31] = TokenData(0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 350, 0, 894298, 0, 0, 2500, 10, "LEGS=dB1B2G3d84G4C5C7B8d295999A9G9d4A7ACAjDAGB1C2C9CACd2D7EBE1FdAFEF6GDGdEGg3:3b:3:3b:6:f67:C:S:G:g5:f6:B:.2:E:g6:.17:B:1:D=293236525469768496g6:Cc:J:20:K:L:M:36:39c:40c:43c:49:g9:Eb:W:21h:Nh");

        // Seed for random mint Ids at test
        _timestamp = block.timestamp;

        // Create token contract
        c9t = new C9Token();

        // Local type to be compatible with c9t.mint
        TokenData[] memory minterData = new TokenData[](32);
        for (uint256 i; i<32; i++) {
            minterData[i] = _rawData[i];
        }

        // Mint NFTs
        c9t.mint(minterData);

        // After minting the owner should have this in ownerOfData
        c9tOwner = address(this);
        balances[c9tOwner] = _rawData.length;
        redemptions[c9tOwner] = 0;
        transfers[c9tOwner] = 0;
        for (uint256 i; i<_rawData.length; i++) {
            votes[c9tOwner] += _rawData[i].votes;
        }
    }

    function _checkOwnerDataOf(address _address)
    private {
        Assert.equal(c9t.balanceOf(_address), balances[_address], "Invalid balanceOf");
        Assert.equal(c9t.redemptionsOf(_address), redemptions[_address], "Invalid redemptionsOf");
        Assert.equal(c9t.transfersOf(_address), transfers[_address], "Invalid transfersOf");
        Assert.equal(c9t.votesOf(_address), votes[_address], "Invalid votesOf");
    } 

    function _getTokenIdVotes(uint256 mintId)
    private view
    returns (uint256 tokenId, uint256 numVotes) {
        tokenId = _rawData[mintId].tokenid;
        numVotes = _rawData[mintId].votes;
    }

    function _getTokenIdsVotes(uint256[] memory mintId)
    private view
    returns (uint256[] memory tokenIds, uint256 numVotes) {
        tokenIds = new uint256[](mintId.length);
        for (uint256 i; i<mintId.length; ++i) {
            (uint256 tokenId, uint256 _numVotes) = _getTokenIdVotes(mintId[i]);
            tokenIds[i] = tokenId;
            numVotes += _numVotes;
        }
    }

    function _checkRoyaltyInfo(uint256 tokenId, uint256 royaltyAmt, address royaltyReceiver)
    private {
        (address receiver, uint256 royalty) = c9t.royaltyInfo(tokenId, 10000);
        Assert.equal(receiver, royaltyReceiver, "Invalid royalty receiver");
        Assert.equal(royalty, royaltyAmt, "Invalid royalty");
    }

    function _checkTokenParams(uint256 mintId)
    private {
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        uint256[21] memory _tokenParams = c9t.getTokenParams(tokenId);
        TokenData memory rawdata = _rawData[mintId];
        Assert.equal(rawdata.upgraded, _tokenParams[3], "Invalid upgraded");
        Assert.equal(rawdata.display, _tokenParams[4], "Invalid display");
        Assert.equal(rawdata.locked, _tokenParams[5], "Invalid locked");
        Assert.equal(rawdata.validity, _tokenParams[2], "Invalid validity");
        Assert.equal(rawdata.cntrytag, _tokenParams[12], "Invalid cntrytag");
        Assert.equal(rawdata.cntrytush, _tokenParams[13], "Invalid cntrytush");
        Assert.equal(rawdata.gentag, _tokenParams[14], "Invalid gentag");
        Assert.equal(rawdata.gentush, _tokenParams[15], "Invalid gentush");
        Assert.equal(rawdata.markertush, _tokenParams[16], "Invalid markertush");
        Assert.equal(rawdata.special, _tokenParams[17], "Invalid special");
        Assert.equal(rawdata.raritytier, _tokenParams[18], "Invalid raritytier");
        Assert.equal(rawdata.tokenid, tokenId, "Invalid tokenid");
        Assert.equal(mintId+1, _tokenParams[11], "Invalid mintid");
        Assert.equal(rawdata.royalty, _tokenParams[19], "Invalid royalty");
        Assert.equal(rawdata.royaltiesdue, _tokenParams[20], "Invalid royaltiesdue");
        Assert.equal(_timestamp, _tokenParams[1], "Invalid validitystamp");
        Assert.equal(_timestamp, _tokenParams[9], "Invalid mintstamp");
        Assert.equal(rawdata.insurance, _tokenParams[6], "Invalid insurance");
        Assert.equal(rawdata.votes, _tokenParams[7], "Invalid votes");
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

    // Transfer Tests

    /* @dev 1. Make sure contract owner, total supply, and owner 
     * data are correct after minting. Check that token combos 
     * exist.
     */ 
    function checkPostMint()
    public {
        Assert.equal(c9tOwner, c9t.owner(), "Invalid owner");
        Assert.equal(c9t.totalSupply(), _rawData.length, "Invalid supply");
        _checkOwnerDataOf(c9tOwner);

        uint256 combo;
        combo = c9t.comboExists(5, 0, 2, 1, 2, 2, "CHILLY") ? 1 : 0;
        Assert.equal(combo, 1, "Invalid combo1");
        combo = c9t.comboExists(6, 0, 2, 1, 3, 2, "CHOCOLATE") ? 1 : 0;
        Assert.equal(combo, 1, "Invalid combo2");
        combo = c9t.comboExists(6, 0, 2, 1, 3, 2, "PATTI") ? 1 : 0;
        Assert.equal(combo, 0, "Invalid combo3");
    }

    /* @dev 2. Checks that all data has been stored and is being 
     * read properly.
     */ 
    function checkTokenParams()
    public {
        for (uint256 i; i<_rawData.length; ++i) {
            _checkTokenParams(i);
        }
    }

    /* @dev 3. Tests upgrade and set display.
     */ 
    function checkSetTokenUpgradedDisplay()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        
        c9t.setTokenUpgraded(tokenId);
        uint256 upgradedSet = c9t.getTokenParams(tokenId)[3];
        Assert.equal(upgradedSet, 1, "Invalid upgraded value");

        c9t.setTokenDisplay(tokenId, true);
        uint256 displaySet = c9t.getTokenParams(tokenId)[4];
        Assert.equal(displaySet, 1, "Invalid display1 set");

        c9t.setTokenDisplay(tokenId, false);
        displaySet = c9t.getTokenParams(tokenId)[4];
        Assert.equal(displaySet, 0, "Invalid display set");
    }

    /* @dev 4. Check to ensure optimized transfer works properly, 
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

    /* @dev 5. Check to ensure optimized batch transfer works properly, 
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

    /* @dev 6. Check to ensure optimized safeTransfer works properly, 
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

    /* @dev 7. Check to ensure optimized batch safeTransferBatch works properly, 
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

    /* @dev 8. Check to ensure optimized batch safeTransferBatchAddress works properly, 
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

    /* @dev 9. Royalties testing - global.
     */ 
    function checkGlobalRoyalties()
    public {
        // Check to make sure info is read correctly
        _checkRoyaltyInfo(0, 500, c9tOwner);
    }

    /* @dev 10. Royalties testing - token level.
     */ 
    function checkResetTokenRoyalties()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        address newReceiver = TestsAccounts.getAccount(3);
        uint256 newRoyaltyAmt = 800;

        // Set the new royalty for the tokens
        c9t.setTokenRoyalty(tokenId, newRoyaltyAmt, newReceiver);

        // Check to make sure updated info is read correctly
        _checkRoyaltyInfo(tokenId, newRoyaltyAmt, newReceiver);

        // Reset royalties
        c9t.resetTokenRoyalty(tokenId);
        _checkRoyaltyInfo(tokenId, 500, c9tOwner);
    }

    /* @dev 11. Royalties due testing.
     */ 
    function checkSetRoyaltiesDue()
    public {
        uint256 mintId = _timestamp % _rawData.length;
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        uint256 royaltiesDue = 8791;
        
        c9t.setTokenValidity(tokenId, ROYALTIES);
        c9t.setRoyaltiesDue(tokenId, royaltiesDue);
        uint256 royaltiesDueSet = c9t.getTokenParams(tokenId)[20];
        Assert.equal(royaltiesDueSet, royaltiesDue, "Invalid royalties due");
    }
}
    