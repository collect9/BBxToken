// SPDX-License-Identifier: GPL-3.0
pragma solidity >0.8.17;

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";

// This import is automatically injected by Remix
import "remix_tests.sol"; 

import "../C9Redeemer.sol";
import "../abstract/C9Struct4.sol";

// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract C9TestContract is C9Struct {

    function afterEach()
    public virtual {
        // 1. Check owner data is still correct
        _checkOwnerDataOf(c9tOwner);
        // 2. Check all token owner params are still correct
        _checkOwnerParams();
        // 3. Check all token data params are still correct
        _checkTokenParams();
    }

    address internal c9tOwner = address(this);

    // Ground truth parameters to compare against
    mapping(address => uint256) internal balances;
    mapping(address => uint256) internal redemptions;
    mapping(address => uint256) internal transfers;
    mapping(address => uint256) internal votes;
    
    mapping(uint256 => uint256) internal tokenTransfers;
    mapping(uint256 => address) internal tokenOwner;
    mapping(uint256 => bool) internal tokenRedeemed;


    bool regStatus;

    // Others to save and check against
    uint256 internal redeemCounter;
    uint256 internal burnCounter;

    // Randomness variable
    uint256 internal _timestamp;

    // Raw data stored to compare tests against
    TokenData[32] internal _rawData;

    // Create contract and mint some NFTs
    C9Redeemable internal c9t;
    
    constructor() {
        // Raw data ground truth
        _rawData[0] = TokenData("CUBBIE", 0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 35, 0, 78081, 0, 0, 2500, 10, 5799085202302367719035234681017398474051095076570857013597817786734685);
        _rawData[1] = TokenData("ROYAL BLUE PEANUT", 0, 0, 0, 0, 0, 5, 1, 3, 1, 4, 1, 3, 0, 35, 0, 72467, 0, 0, 2800, 6, 5799151008014567951206005882768312063662414510760790137393226684311161);
        _rawData[2] = TokenData("VALENTINO", 0, 0, 0, 0, 0, 6, 0, 2, 1, 3, 2, 2, 0, 35, 0, 71092, 0, 0, 2750, 8, 5799322928678693543339885123734541867255269856302548571350708924197061);
        _rawData[3] = TokenData("NANA", 0, 0, 0, 0, 0, 6, 1, 3, 1, 0, 1, 4, 0, 42, 0, 78860, 0, 0, 750, 4, 5799261325534556531652587271049251217401254928623443028996730623403188);
        _rawData[4] = TokenData("DIGGER 4C", 0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 3, 1, 0, 32, 0, 75909, 0, 0, 5000, 12, 5798992985372722354928123939770910365360021735675541569933454565185909);
        _rawData[5] = TokenData("PATTI DF", 0, 0, 0, 0, 0, 5, 4, 1, 1, 1, 0, 3, 0, 37, 0, 78858, 0, 0, 1750, 4, 5799299133572861857095104203472571445270804961947979386271633777498445);
        _rawData[6] = TokenData("TEDDY OF BROWN", 0, 0, 0, 0, 0, 6, 0, 1, 1, 0, 0, 4, 0, 37, 0, 75965, 0, 0, 1500, 3, 5799110630512146088800439073471481610924163883948999686531490092167061);
        _rawData[7] = TokenData("VALENTINO", 0, 0, 0, 0, 0, 5, 0, 2, 1, 3, 2, 2, 0, 35, 0, 77354, 0, 0, 2750, 8, 5799041541381024168875465607857974275404531404865957850426330021901249);
        _rawData[8] = TokenData("LUCKY", 0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 3, 0, 37, 0, 78605, 0, 0, 1500, 4, 5799313086989387711163174239864080429988347410299820013197334403487773);
        _rawData[9] = TokenData("TEDDY JADE", 0, 0, 0, 0, 0, 5, 0, 2, 1, 3, 2, 2, 0, 37, 0, 75455, 0, 0, 2000, 8, 5798950331564097027970498315779704321036331570146711793872098883803669);
        _rawData[10] = TokenData("SPEEDY", 0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 47, 0, 79040, 0, 0, 350, 2, 5799085136859462779615240208690914199280003213012462018833458607568533);
        _rawData[11] = TokenData("MAGIC ", 0, 0, 0, 0, 0, 4, 4, 3, 1, 4, 0, 5, 0, 50, 0, 893383, 0, 0, 150, 2, 24323067577172945111941234948813021016828972050109700996060327482980928460485);
        _rawData[12] = TokenData("TEDDY OF MAGENTA", 0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 4, 0, 37, 0, 893852, 0, 0, 1500, 3, 24324006349475856426811923192785636513123608320961454462369156219212602684853);
        _rawData[13] = TokenData("QUACKER WINGLESS", 0, 0, 0, 0, 0, 6, 0, 1, 1, 0, 0, 2, 0, 37, 0, 74346, 0, 0, 2000, 5, 5799044126597135191852243175168869866908769677255147363293785611843565);
        _rawData[14] = TokenData("WEB", 0, 0, 0, 0, 0, 6, 1, 1, 1, 0, 0, 4, 0, 40, 0, 78466, 0, 0, 1400, 3, 5799235823808539593533276756374347554037635227357417672212094986621645);
        _rawData[15] = TokenData("TRAP", 0, 0, 0, 0, 0, 4, 4, 3, 1, 4, 0, 5, 0, 45, 0, 77478, 0, 0, 500, 2, 5799314716856311493516378775614790722696653181015404420863147306134753);
        _rawData[16] = TokenData("TRAP", 0, 0, 0, 0, 0, 5, 0, 2, 1, 3, 2, 2, 0, 37, 0, 77367, 0, 0, 2000, 8, 5799278534612464040165726399584244766659862416419901194389094087959768);
        _rawData[17] = TokenData("INCH", 0, 0, 0, 0, 0, 4, 4, 3, 1, 4, 0, 5, 0, 50, 0, 74948, 0, 0, 150, 2, 5799007120822452303200704454392590427633529446221086386498370980817725);
        _rawData[18] = TokenData("TEDDY TEAL", 0, 0, 0, 0, 0, 6, 1, 3, 1, 0, 0, 6, 0, 47, 0, 895888, 0, 0, 450, 1, 24322732791925231718597901896464011127582813720259393431057243199358812947445);
        _rawData[19] = TokenData("TEDDY CRANBERRY", 0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 45, 0, 78591, 0, 0, 500, 2, 5798983259372559259649478704865102183114154979838594398866019831122125);
        _rawData[20] = TokenData("HUMPHREY", 0, 0, 0, 0, 0, 2, 4, 2, 1, 0, 0, 3, 0, 40, 0, 69188, 0, 0, 1200, 4, 5799013643381221588450837742827111648583644710826998940564420110716389);
        _rawData[21] = TokenData("SPOT", 0, 0, 0, 0, 0, 5, 1, 2, 1, 0, 0, 5, 0, 45, 0, 72234, 0, 0, 500, 2, 5799150966230647930746103710616971580641429829876839399125819173912201);
        _rawData[22] = TokenData("BROWNIE", 0, 0, 0, 0, 0, 5, 4, 1, 1, 1, 1, 3, 0, 37, 0, 77616, 0, 0, 1800, 6, 5798998803632052044888682303290780771600572991840346580834347215763745);
        _rawData[23] = TokenData("SPLASH", 0, 0, 0, 0, 0, 5, 4, 0, 1, 1, 0, 2, 0, 35, 0, 78077, 0, 0, 2500, 10, 5799277778962795249624098336453211151371729106509768896000264210351389);
        _rawData[24] = TokenData("SPOOK", 0, 0, 0, 0, 0, 5, 1, 3, 1, 4, 0, 5, 0, 47, 0, 72535, 0, 0, 350, 2, 5799134626889714050492983678154145488816434763104877355262923114034857);
        _rawData[25] = TokenData("GOLDIE", 0, 0, 0, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 47, 0, 77003, 0, 0, 300, 2, 5799241467364358421928659436044716419926730545198957899099418689026081);
        _rawData[26] = TokenData("TEDDY OF CRANBERRY", 0, 0, 0, 0, 0, 2, 4, 2, 1, 5, 0, 5, 0, 42, 0, 76090, 0, 0, 750, 2, 5799282743624756829579178850235960144078557193791151690439773890808985);
        _rawData[27] = TokenData("ALLY", 0, 0, 0, 0, 0, 5, 1, 3, 1, 4, 0, 5, 0, 50, 0, 893379, 0, 0, 200, 2, 24322943308668699081434806879740272793683024287520481799047116943370226370997);
        _rawData[28] = TokenData("TEDDY OF MAGENTA", 0, 0, 1, 0, 0, 6, 1, 2, 1, 0, 0, 5, 0, 45, 0, 78274, 0, 0, 500, 2, 5799040797830861292230812403166935521563202740289193265615463921626077);
        _rawData[29] = TokenData("DERBY CM", 0, 0, 1, 0, 0, 6, 1, 3, 1, 0, 0, 6, 0, 50, 0, 76015, 0, 0, 125, 1, 5798952723946465783293057815368373566671191673007074447422925889605209);
        _rawData[30] = TokenData("ALLY", 0, 0, 0, 0, 0, 2, 4, 2, 1, 0, 0, 4, 0, 45, 0, 69358, 0, 0, 500, 3, 5799208630858884874046788132325762798534203686929889537546296853407797);
        _rawData[31] = TokenData("FLASH", 0, 0, 0, 4, 0, 6, 4, 1, 1, 1, 0, 4, 0, 37, 0, 894296, 0, 0, 1500, 3, 24323467797581229811197741915687639246135400876943092544792468055570397136869);

        // Create NFT contract instance
        c9t = new C9Redeemable();

        // Seed for random mint Ids at test
        _timestamp = block.timestamp;

        // Local type to be compatible with c9t.mint
        TokenData[] memory minterData = new TokenData[](32);
        for (uint256 i; i<32; i++) {
            _rawData[i].validitystamp = _timestamp;
            minterData[i] = _rawData[i];
            tokenOwner[_rawData[i].tokenid] = c9tOwner; // Set minter as owner
        }

        // Mint NFTs
        c9t.mint(minterData);

        // After minting the owner should have this in ownerOfData
        balances[c9tOwner] = _rawData.length;
        redemptions[c9tOwner] = 0;
        transfers[c9tOwner] = 0;
        for (uint256 i; i<_rawData.length; i++) {
            votes[c9tOwner] += _rawData[i].votes;
        }
    }

    

    /* @dev Returns ownerData.
     */
    function _checkOwnerDataOf(address _address)
    internal {
        Assert.equal(c9t.balanceOf(_address), balances[_address], "Invalid balanceOf");
        Assert.equal(c9t.transfersOf(_address), transfers[_address], "Invalid transfersOf");
        Assert.equal(c9t.votesOf(_address), votes[_address], "Invalid votesOf");
        Assert.equal(c9t.isRegistered(_address), regStatus, "Invalid regStatus");
        Assert.equal(c9t.redemptionsOf(_address), redemptions[_address], "Invalid redemptionsOf");
    }

    /* @dev Checks the minted token params.
     */
    function _checkTokenParams(uint256 mintId)
    internal {
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        uint256[11] memory _tokenParams = c9t.getTokenParams(tokenId);
        TokenData memory rawdata = _rawData[mintId];

        Assert.equal(_tokenParams[0], _timestamp, "Invalid mintstamp");
        Assert.equal(_tokenParams[3], rawdata.cntrytag, "Invalid cntrytag");
        Assert.equal(_tokenParams[4], rawdata.cntrytush, "Invalid cntrytush");
        Assert.equal(_tokenParams[5], rawdata.gentag, "Invalid gentag");
        Assert.equal(_tokenParams[6], rawdata.gentush, "Invalid gentush");
        Assert.equal(_tokenParams[7], rawdata.markertush, "Invalid markertush");
        Assert.equal(_tokenParams[8], rawdata.special, "Invalid special");
        Assert.equal(_tokenParams[9], rawdata.raritytier, "Invalid raritytier");
        Assert.equal(_tokenParams[10], rawdata.royaltiesdue, "Invalid royalties due");
    }

    /* @dev Checks the minted owner params.
     */
    function _checkOwnerParams(uint256 mintId)
    internal {
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        uint256[9] memory _ownerParams = c9t.getOwnersParams(tokenId);
        TokenData memory rawdata = _rawData[mintId];

        // actual, expected
        Assert.equal(_ownerParams[0], tokenTransfers[tokenId], "Invalid xfer counter");
        Assert.equal(_ownerParams[1], rawdata.validitystamp, "Invalid validitystamp");
        Assert.equal(_ownerParams[2], rawdata.validity, "Invalid validity");
        Assert.equal(_ownerParams[3], rawdata.upgraded, "Invalid upgraded");
        Assert.equal(_ownerParams[4], rawdata.display, "Invalid display");
        Assert.equal(_ownerParams[5], rawdata.locked, "Invalid locked");
        Assert.equal(_ownerParams[6], rawdata.insurance, "Invalid insurance");
        Assert.equal(_ownerParams[7], rawdata.royalty*10, "Invalid royalty");
        Assert.equal(_ownerParams[8], rawdata.votes, "Invalid votes");
    }

    function _checkViewFunctions(uint256 mintId)
    internal {
        (uint256 tokenId,) = _getTokenIdVotes(mintId);
        TokenData memory rawdata = _rawData[mintId];

        // actual, expected
        uint256 _islocked = c9t.isLocked(tokenId) ? 1 : 0;
        Assert.equal(_islocked, rawdata.locked, "Invalid view locked");
        uint256 _isupgraded = c9t.isUpgraded(tokenId) ? 1 : 0;
        Assert.equal(_isupgraded, rawdata.upgraded, "Invalid view upgraded");
        Assert.equal(c9t.validityStatus(tokenId), rawdata.validity, "Invalid view validity status");
        Assert.equal(c9t.ownerOf(tokenId), tokenOwner[tokenId], "Invalid view owner");
        Assert.equal(c9t.getTokenParamsName(tokenId), rawdata.name, "Invalid view name");
        (, uint256 _royaltyinfo) = c9t.royaltyInfo(tokenId, 10000);
        Assert.equal(_royaltyinfo, rawdata.royalty*10, "Invalid view royalty info");
        Assert.equal(c9t.preRedeemable(tokenId), true, "Invalid view preredeemable");
        Assert.equal(c9t.isRedeemable(tokenId), false, "Invalid view redeemable");
        Assert.equal(c9t.isRedeemed(tokenId), tokenRedeemed[tokenId], "Invalid view redeemaed");
    }

    function checkTotalSupply()
    public {
         Assert.equal(c9t.totalSupply(), _rawData.length, "Invalid total supply");
    }

    /* @dev Returns number of votes for the minted token.
     */
    function _getTokenIdVotes(uint256 mintId)
    internal view
    returns (uint256 tokenId, uint256 numVotes) {
        tokenId = _rawData[mintId].tokenid;
        numVotes = _rawData[mintId].votes;
    }

    /* @dev Returns number of votes for the minted tokens list.
     */
    function _getTokenIdsVotes(uint256[] memory mintId)
    internal view
    returns (uint256[] memory tokenIds, uint256 numVotes) {
        tokenIds = new uint256[](mintId.length);
        for (uint256 i; i<mintId.length; ++i) {
            (uint256 tokenId, uint256 _numVotes) = _getTokenIdVotes(mintId[i]);
            tokenIds[i] = tokenId;
            numVotes += _numVotes;
        }
    }

    function _grantRole(bytes32 role, address account)
        internal {
            if (!c9t.hasRole(role, account)) {
                c9t.grantRole(role, account);
                Assert.equal(c9t.hasRole(role, account), true, "Role grant failure");
            }
    }

    function _setValidityStatus(uint256 mintId, uint256 tokenId, uint256 status)
    internal {
        // 1. Set raw data ground truth
        _rawData[mintId].validity = status; 
        _rawData[mintId].validitystamp = block.timestamp;
        if (status >= REDEEMED) {
            _rawData[mintId].locked = LOCKED;
        }

        // 2. Set token validity
        c9t.setTokenValidity(tokenId, status);
        
        // 3. Make sure validity status method is getting correct result
        uint256 validityStatus = c9t.validityStatus(tokenId);
        Assert.equal(validityStatus, status, "Invalid validity status");

        // 4. Make sure all token params match ground truth
        _checkTokenParams(mintId);
    }

    /* @dev 1. Make sure contract owner, total supply, and owner 
     * data are correct after minting. Check that token combos 
     * exist.
     */ 
    function checkPostMint()
    public {
        Assert.equal(c9t.owner(), c9tOwner, "Invalid owner");
        Assert.equal(c9t.totalSupply(), _rawData.length, "Invalid supply");
    }

    /* @dev 2. Checks that all data has been stored and is being 
     * read properly by the viewer function.
     */
    function checkTokenParams()
    public {
        _checkTokenParams();
    }

    function _checkTokenParams()
    private {
        for (uint256 i; i<_rawData.length; ++i) {
            _checkTokenParams(i);
        }
    }

    /* @dev 3. Checks that all data has been stored and is being 
     * read properly by the viewer function.
     */ 
    function checkOwnerParams()
    public {
        _checkOwnerParams();
    }

    function _checkOwnerParams()
    private {
        for (uint256 i; i<_rawData.length; ++i) {
            _checkOwnerParams(i);
        }
    }

    function checkMintEdCounter()
    public {
        uint256 mintSupply;
        for (uint256 i; i<99;) {
            mintSupply += c9t.getEditionMaxMintId(i);
            unchecked {++i;}
        }
        Assert.equal(c9t.totalSupply(), mintSupply, "Invalid mint counter supply");
    }
}