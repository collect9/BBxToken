//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
//import "./VRFConsumerBaseV2a.sol";

contract C9RandomSeed is VRFConsumerBaseV2 {
    error StatusRequestDoesNotExist(uint256 requestId);

    event VRFPreRequest(
        address indexed requester,
        uint256 indexed numberOfMints
    );
    event RequestSent(
        uint256 indexed requestId,
        uint256 indexed numberOfMints
    );
    event RequestFulfilled(
        uint256 indexed requestId,
        uint256 indexed randomWord
    );

    VRFCoordinatorV2Interface COORDINATOR;
    uint256 internal _requestBatchSize;

    // Your subscription ID.
    uint64 constant SUB_ID = 39;
    //uint64 constant SUB_ID = 10415;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    //bytes32 constant KEY_HASH = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    // The default is 3, but you can set this higher.
    uint16 constant REQ_CONFIRMATIONS = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 constant NUM_WORDS = 1;

    uint32 constant GAS_LIMIT = 250000;

    /**
     * SEPOLIA
     * COORDINATOR: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     */
    constructor(address coordinator)
        VRFConsumerBaseV2(coordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(coordinator);
    }

    function preRequestRandomWords(address requester, uint256 numberOfMints)
        internal virtual {
            _requestBatchSize += numberOfMints;
            emit VRFPreRequest(requester, numberOfMints);
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords()
        internal virtual {
            // Will revert if subscription is not set and funded.
            uint256 numberOfMints = _requestBatchSize;
            uint256 _gasLimit = GAS_LIMIT + 8000*numberOfMints;
            uint256 requestId = COORDINATOR.requestRandomWords(
                KEY_HASH,
                SUB_ID,
                REQ_CONFIRMATIONS,
                uint32(_gasLimit),
                NUM_WORDS
            );
            emit RequestSent(requestId, numberOfMints);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords)
        internal virtual override {
            emit RequestFulfilled(_requestId, _randomWords[0]);
    }

    function pendingRequests()
        external virtual
        returns (uint256) {
            return _requestBatchSize;
        }
}