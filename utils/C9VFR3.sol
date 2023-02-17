//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract C9RandomSeed is VRFConsumerBaseV2 {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256 randomWords);

    VRFCoordinatorV2Interface COORDINATOR;

    struct RequestStatus {
        address requester;
        uint96 numberOfMints;
    }
    mapping(uint256 => RequestStatus) internal statusRequests;

    // Your subscription ID.
    uint64 constant SUB_ID = 39;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 constant CALL_BACK_GAS_LIMIT = 50000;

    // The default is 3, but you can set this higher.
    uint16 constant REQ_CONFIRMATIONS = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 constant NUM_WORDS = 1;

    /**
     * SEPOLIA
     * COORDINATOR: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
     */
    constructor(address coordinator)
        VRFConsumerBaseV2(coordinator) {
            COORDINATOR = VRFCoordinatorV2Interface(coordinator);
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords(address requester, uint256 numberOfMints)
        internal {
            // Will revert if subscription is not set and funded.
            uint256 gasLimit = CALL_BACK_GAS_LIMIT*numberOfMints;
            uint256 requestId = COORDINATOR.requestRandomWords(
                KEY_HASH,
                SUB_ID,
                REQ_CONFIRMATIONS,
                uint32(gasLimit),
                NUM_WORDS
            );
            statusRequests[requestId] = RequestStatus(requester, uint96(numberOfMints));
            emit RequestSent(requestId, NUM_WORDS);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory /*_randomWords*/)
        internal virtual override {
            if (statusRequests[_requestId].numberOfMints == 0) {
                revert("Status request does not exist.");
            }
    }
}