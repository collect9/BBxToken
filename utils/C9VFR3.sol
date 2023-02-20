//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
//import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "./VRFConsumerBaseV2a.sol";

contract C9RandomSeed is VRFConsumerBaseV2 {
    error StatusRequestDoesNotExist(uint256 requestId);

    event RequestSent(
        uint256 indexed requestId,
        address indexed requester,
        uint256 indexed numberOfMints
    );
    event RequestFulfilled(
        uint256 indexed requestId,
        uint256 indexed randomWord
    );

    VRFCoordinatorV2Interface COORDINATOR;
    mapping(uint256 => uint256) internal statusRequests;

    // Your subscription ID.
    uint64 constant SUB_ID = 39;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    // The default is 3, but you can set this higher.
    uint16 constant REQ_CONFIRMATIONS = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 constant NUM_WORDS = 1;

    uint32 constant GAS_LIMIT = 200000;

    /**
     * SEPOLIA
     * COORDINATOR: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     */
    constructor(address coordinator)
        VRFConsumerBaseV2(coordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(coordinator);
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords(address requester, uint256 tokenId, uint256 numberOfMints)
        internal virtual {
            // Will revert if subscription is not set and funded.
            uint256 requestId = COORDINATOR.requestRandomWords(
                KEY_HASH,
                SUB_ID,
                REQ_CONFIRMATIONS,
                GAS_LIMIT,
                NUM_WORDS
            );
            uint256 _requestInfo = tokenId;
            _requestInfo |= numberOfMints<<24;
            statusRequests[requestId] = _requestInfo;
            emit RequestSent(requestId, requester, numberOfMints);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords)
        internal virtual override {
            if (statusRequests[_requestId] == 0) {
                revert StatusRequestDoesNotExist(_requestId);
            }
            emit RequestFulfilled(_requestId, _randomWords[0]);
    }
}