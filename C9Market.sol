// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "./C9OwnerControl.sol";
import "./C9Token.sol";
import "./utils/EthPricer.sol";

uint256 constant MPOS_ACTIVE = 0;
uint256 constant MPOS_TIMESTAMP = 8;
uint256 constant MPOS_PRICEMIN = 56;
uint256 constant MPOS_PRICEMAX = 88;
uint256 constant MPOS_DRIFT = 96;

uint256 constant DEACTIVATE = 0;
uint256 constant ACTIVATE = 1;

error ListingAlreadyActive(uint256 tokenId);
error ListingAlreadyExists(uint256 tokenId);
error ListingAlreadyDeactivated(uint256 tokenId);
error ListingNotActive(uint256 tokenId);
error MinPriceTooLow(uint256 tokenId, uint256 floorPrice, uint256 received);
error NoListingFound(uint256 tokenId);

interface IC9Market {
    function getTokenUSDPrice(uint256 _tokenId) external view returns (uint256);
    function isListed(uint256 _tokenId) external view returns (bool);
    function purchaseToken(uint256 _tokenId) external payable;
    function purchaseTokenBatch(uint256[] calldata _tokenId) external payable;  
}

contract C9Market is IC9Market, C9OwnerControl {
    address payable public Payee;
    uint96 private _floorPrice = 100;
    
    address private contractPricer;
    address private immutable contractToken;

    struct ListingStruct {
        uint256 tokenId;
        uint256 active;
        uint256 priceMin;
        uint256 priceMax;
        uint256 priceDrift;
    }

    mapping(uint256 => uint256) _tokenListing; //active(u8), timestamp (u48), minprice (u32), maxprice (u32), drift(u8),
    
    event Purchase(
        address indexed tokenBuyer,
        uint256 indexed tokenId,
        uint256 indexed totalPrice
    );
    event PurchaseBatch(
        address indexed tokenBuyer,
        uint256[] indexed tokenId,
        uint256 indexed totalPrice
    );

    constructor(address _contractToken) {
        contractToken = _contractToken;
        Payee = payable(msg.sender); 
    }

    modifier listingExists(uint256 _tokenId) {
        if (_tokenListing[_tokenId] == 0) {
            revert NoListingFound(_tokenId);
        }
        _;
    }

    /**
     * @dev Activates a listing if not activated. This is far cheaper 
     * than deleting and listing again, and also slightly cheaper than 
     * using the update method.
     */
    function _activate(uint256 _tokenId)
        private
        listingExists(_tokenId) {
            uint256 _listingData = _tokenListing[_tokenId];
            if (uint256(uint8(_listingData>>MPOS_ACTIVE)) == ACTIVATE) {
                revert ListingAlreadyActive(_tokenId);
            }
            _tokenListing[_tokenId] = _setPackedParam(
                _listingData,
                MPOS_ACTIVE,
                ACTIVATE,
                type(uint8).max
            );
    }

    /**
     * @dev Removes token from marketplace.
     */
    function _cancel(uint256 _tokenId)
        private
        listingExists(_tokenId) {
            delete _tokenListing[_tokenId];
    }

    /**
     * @dev Deactivates listing. This is cheaper than removing 
     * and relisting.
     */
    function _deactivate(uint256 _tokenId)
        private
        listingExists(_tokenId) {
            uint256 _listingData = _tokenListing[_tokenId];
            if (uint256(uint8(_listingData>>MPOS_ACTIVE)) == DEACTIVATE) {
                revert ListingAlreadyDeactivated(_tokenId);
            }
            _tokenListing[_tokenId] = _setPackedParam(
                _listingData,
                MPOS_ACTIVE,
                DEACTIVATE,
                type(uint8).max
            );
    }
    
    /**
     * Internal for _list and _update.
     */
    function _createListing(ListingStruct calldata _listingStruct)
        private {
            uint256 _tokenId = _listingStruct.tokenId;
            uint256 _listingPriceMin = _listingStruct.priceMin;
            if (_listingPriceMin < _floorPrice) {
                revert MinPriceTooLow(_tokenId, _floorPrice, _listingPriceMin);
            }

            // Create the packed listing
            uint256 _listingData;
            _listingData |= _listingStruct.active<<MPOS_ACTIVE;
            _listingData |= block.timestamp<<MPOS_TIMESTAMP;
            _listingData |= _listingPriceMin<<MPOS_PRICEMIN;
            _listingData |= _listingStruct.priceMax<<MPOS_PRICEMAX;
            _listingData |= _listingStruct.priceDrift<<MPOS_DRIFT;

            // Save to storage
            _tokenListing[_tokenId] = _listingData;
    }

    /**
     * Add a token to the marketplace.
     */
    function _list(ListingStruct calldata _listingStruct)
        private {
            uint256 _tokenId = _listingStruct.tokenId;
            // This adds about 5k gas per batched... considering removing?
            address _tokenOwner = C9Token(contractToken).ownerOf(_tokenId);
            if (msg.sender != _tokenOwner) {
                revert Unauthorized();
            }
            if (_tokenListing[_tokenId] != 0) {
                revert ListingAlreadyExists(_tokenId);
            }
            _createListing(_listingStruct);
    }

    /*
     * @dev Resets the listing timestamp for tokenId.
     */
    function _reset(uint256 _tokenId)
        private
        listingExists(_tokenId) {
            _tokenListing[_tokenId] = _setPackedParam(
                _tokenListing[_tokenId],
                MPOS_TIMESTAMP,
                block.timestamp,
                type(uint48).max
            );
    }

    /*
     * @dev Set value within the packed param.
     */
    function _setPackedParam(uint256 _packedToken, uint256 _pos, uint256 _val, uint256 _mask)
        private pure
        returns(uint256) {
            _packedToken &= ~(_mask<<_pos); //zero out only its portion
            _packedToken |= _val<<_pos; //write value back in
            return _packedToken;
    }

    /*
     * @dev Updates listing within in the marketplace.
     */
    function _update(ListingStruct calldata _listingStruct)
        internal
        listingExists(_listingStruct.tokenId) {
            _createListing(_listingStruct);
    }

    // >>>>>> BATCHES ARE CHEAPER

    /*
     * @dev Activate tokens that are deactivated.
     */
    function activateBatch(uint256[] calldata _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _activate(_tokenId[i]);
                unchecked {++i;}
            }
    }

    /*
     * @dev Cancel token listings.
     */
    function cancelBatch(uint256[] calldata _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _cancel(_tokenId[i]);
                unchecked {++i;}
            }
    }

    /*
     * @dev Deactivate active token listings.
     */
    function deactivateBatch(uint256[] calldata _tokenId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                _deactivate(_tokenId[i]);
                unchecked {++i;}
            }
    }

    /*
     * @dev Add tokens to marketplace.
     */
    function listBatch(ListingStruct[] calldata _listingStruct)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _listingStruct.length;
            for (uint i; i<_batchSize;) {
                _list(_listingStruct[i]);
                unchecked {++i;}
            }
    }

    /*
     * @dev Update existing tokens in marketplace.
     */
    function updateBatch(ListingStruct[] calldata _listingStruct)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            uint256 _batchSize = _listingStruct.length;
            for (uint i; i<_batchSize;) {
                _update(_listingStruct[i]);
                unchecked {++i;}
            }
    }

    /**
     * @dev For the frontend to easily look up if the token is listed.
     * If listed then it can proceed to getListingData.
     */
    function isListed(uint256 _tokenId)
        external view override
        returns (bool) {
            bool _listed = _tokenListing[_tokenId] == 0 ? false: true;
            return _listed;
    }

    /**
     * Returns packed token info in separate uint256.
     */
    function getListingData(uint256 _tokenId)
        public view
        listingExists(_tokenId)
        returns (
            uint256 active,
            uint256 timestamp,
            uint256 minPrice,
            uint256 maxPrice,
            uint256 priceDrift
        ) {
            uint256 _listingData = _tokenListing[_tokenId];
            active = uint256(uint8(_listingData>>MPOS_ACTIVE));
            timestamp = uint256(uint8(_listingData>>MPOS_TIMESTAMP));
            minPrice = uint256(uint8(_listingData>>MPOS_PRICEMIN));
            maxPrice = uint256(uint8(_listingData>>MPOS_PRICEMAX));
            priceDrift = uint256(uint8(_listingData>>MPOS_DRIFT));
    }

    /**
     * Returns the token price in USDC integer format.
     * The front-end can display this result as-is.
     */
    function getTokenUSDPrice(uint256 _tokenId)
        public view override
        returns (uint256) {
            // Get the listed token data
            (,
            uint256 _listingTimestamp,
            uint256 _minPrice,
            uint256 _maxPrice,
            uint256 _priceDrift
            ) = getListingData(_tokenId);
            
            // Adjust price if drifter is set
            uint256 _adjustment = 100;
            if (_priceDrift == 1) {
                uint256 dt = block.timestamp - _listingTimestamp;
                _adjustment = (31536000 - dt + 86400) * 50 / 31536000 + 50;
            }
            uint256 _tokenUSDPrice = _maxPrice * _adjustment / 100;
            
            // Make sure adjustment doesn't error out price of bounds
            if (_tokenUSDPrice < _minPrice) {
                return _minPrice;
            }
            else if (_tokenUSDPrice > _maxPrice) {
                return _maxPrice;
            }
            else {
                return _tokenUSDPrice;
            }
    }

    function getTokenBatchUSDPrice(uint256[] calldata _tokenId)
        public view
        returns (uint256 _batchPrice) {
            uint256 _batchSize = _tokenId.length;
            for (uint i; i<_batchSize;) {
                _batchPrice += getTokenUSDPrice(_tokenId[i]);
                unchecked {++i;}
            }
    }

    /**
     * Function that handles purchase. Amount in ETH is calculated, 
     * user must send and then token is sent to user.
     * The token's contract address must have this address approved 
     * to make token transfers from it.
     * Note: frontend will call getTokenUSDPrice, and then 
     * getTokenWeiPrice from the ETH pricer contract.
     */
    function _pay(uint256 _value) 
        private {
        if (msg.value != _value) {
            revert InvalidPaymentAmount(_value, msg.value);
        }
        (bool success,) = payable(Payee).call{value: msg.value}("");
        if(!success) {
            revert PaymentFailure();
        }
    }

    function purchaseToken(uint256 _tokenId)
        external payable override {
            uint256 _totalUSDPrice = getTokenUSDPrice(_tokenId);
            uint256 _totalWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_totalUSDPrice);
            _pay(_totalWeiPrice);
            C9Token(contractToken).safeTransferFrom(address(this), msg.sender, _tokenId);
            _cancel(_tokenId);
            emit Purchase(msg.sender, _tokenId, _totalUSDPrice);
    }

    function purchaseTokenBatch(uint256[] calldata _tokenId)
        external payable override {
            uint256 _totalUSDPrice = getTokenBatchUSDPrice(_tokenId);
            uint256 _totalWeiPrice = IC9EthPriceFeed(contractPricer).getTokenWeiPrice(_totalUSDPrice);
            _pay(_totalWeiPrice);
            uint256 _batchSize = _tokenId.length;
            for (uint256 i; i<_batchSize;) {
                C9Token(contractToken).safeTransferFrom(address(this), msg.sender, _tokenId[i]);
                _cancel(_tokenId[i]);
                unchecked {++i;}
            }
            emit PurchaseBatch(msg.sender, _tokenId, _totalUSDPrice);
    }

    /**
     * @dev Sets the pricer contract.
     */
    function setContractPricer(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (contractPricer == _address) {
                revert AddressAlreadySet();
            }
            contractPricer = _address;
    }

    /**
     * Sets the min listing floor price.
     */
    function setFloorPrice(uint256 _newFloorPrice)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (_newFloorPrice == _floorPrice) {
                revert ValueAlreadySet();
            }
            _floorPrice = uint96(_newFloorPrice);
    }

    /**
     * Sets the payee address. Note this does not 
     * change owner.
     */
    function setPayee(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE) {
            if (Payee == _address) {
                revert AddressAlreadySet();
            }
            Payee = payable(_address);
    }
}