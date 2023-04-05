// SPDX-License-Identifier: MIT
pragma solidity >0.8.17;

abstract contract C9ERC721Storage {
    // Token name
    string public name;

    // Token symbol
    string public symbol;

    // Total supply
    uint256 internal _totalSupply;

    // Total votes
    uint256 internal _totalVotes;
    
    // Mapping from token ID to owner address
    // Updated to be packed, uint160 (default address) with 96 extra bits of custom storage
    mapping(uint256 => uint256) internal _owners;

    // Mapping owner address to token count
    /* Updated to be packed freeing storage for any address mapping information. Balance
       doesn't need to be any larger than the maxTokenId type can possibly reach. */
    mapping(address => uint256) internal _balances;

    // Mapping from token ID to approved address
    /* Updated to be packed, uint160 (default address) with 96 extra bits of custom storage.
       Note that tokenApprovals are not often used by users, so this storage space should 
       only be used as a last resort.
       Note that even not using the extra storage, this has been tested to not add any 
       transfer gas costs, and in fact even reduced it slightly.*/
    mapping(uint256 => uint256) internal _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    /* Basic royalties info. Note that EIP-2981 assigns per token which is a waste 
       if all tokens will have the same royalty.*/
    address internal _royaltyReceiver;
    uint96 internal _royalty;
}



abstract contract C9TokenStorage {
    /**
     * @dev Contracts this token contract interacts with.
     */
    address internal contractMeta;
    address internal contractUpgrader;
    address internal contractVH;
 
    /**
     * @dev Flag that may enable external (IPFS) artwork 
     * versions to be displayed in the future. The _baseURI
     * is a string[2]: index 0 is active and index 1 is 
     * for inactive.
     */
    bool internal _svgOnly;
    string[2] internal _baseURIArray;

    /**
     * @dev Contract-level meta data for OpenSea.
     * OpenSea: https://docs.opensea.io/docs/contract-level-metadata
     */
    string internal _contractURI;

    /**
     * @dev Redemption definitions and events. preRedeemablePeriod 
     * defines how long a token must exist before it can be 
     * redeemed.
     */
    uint24[] internal _burnedTokens;
    uint256 public preRedeemablePeriod; //seconds

    /**
     * @dev Mappings that hold all of the token info required to 
     * construct the 100% on chain SVG.
     * Many properties within _uTokenData that define 
     * the physical collectible are immutable by design.
     */
    mapping(uint256 => address) internal _rTokenData;
    mapping(uint256 => uint256) internal _cTokenData;
    mapping(uint256 => uint256) internal _uTokenData;

    /**
     * @dev _mintId stores the edition minting for up to 99 editions.
     * This means that 99 of some physical collectible, differentiated 
     * only by authentication certificate id can be minted. The limit 
     * is 99 due to the SVG only being able to display 2 digits.
     */
    uint16[99] internal _mintId;
}



abstract contract C9RedeemerStorage {
    bool internal _frozenRedeemer;
    address internal contractPricer;
    uint24[] internal _redeemedTokens;
}



abstract contract C9Eternal is C9ERC721Storage, C9TokenStorage, C9RedeemerStorage {
    
}