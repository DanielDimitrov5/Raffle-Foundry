// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEther();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded();

    enum RaffleState {
        Open,
        CalculatingWinner
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 public immutable i_ticketPrice;
    address payable[] private s_players;
    // @dev Duration of the lottery n seconds
    uint256 private immutable i_interval;
    uint256 private s_startTime;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable gasLane;
    uint64 private immutable s_subscriptionId;
    uint32 private immutable callbackGasLimit;
    address private s_recentWinner;
    RaffleState public s_raffleState;

    event TicketBought(address indexed buyer, uint256 ticketPrice);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 _ticketPrice,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_ticketPrice = _ticketPrice;
        i_interval = _interval;
        s_startTime = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        gasLane = _gasLane;
        s_subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        s_raffleState = RaffleState.Open;
    }

    function buyTicket() public payable {
        if (msg.value < i_ticketPrice) revert Raffle__NotEnoughEther();

        if (s_raffleState == RaffleState.CalculatingWinner) revert Raffle__RaffleNotOpen();

        s_players.push(payable(msg.sender));

        emit TicketBought(msg.sender, msg.value);
    }

    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = block.timestamp - s_startTime >= i_interval;
        bool isOpen = s_raffleState == RaffleState.Open;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("0x0");

        if (!upkeepNeeded) revert Raffle__UpkeepNotNeeded();

        s_raffleState = RaffleState.CalculatingWinner;
        i_vrfCoordinator.requestRandomWords(
            gasLane, s_subscriptionId, REQUEST_CONFIRMATIONS, callbackGasLimit, NUM_WORDS
        );
    }

    function fulfillRandomWords(uint256 /* _requestId */, uint256[] memory _randomWords) internal override {
        uint256 winnerIndex = _randomWords[0] % s_players.length;
        address payable winner = s_players[winnerIndex];
        s_recentWinner = winner;
        s_raffleState = RaffleState.Open;

        s_players = new address payable[](0);
        s_startTime = block.timestamp;

        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) revert Raffle__TransferFailed();

        emit WinnerPicked(winner);
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_startTime;
    }

    function getLastWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return s_players;
    }
}
