// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console, console2} from "forge-std/Test.sol";
import {Raffle} from "../../src/raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from
    "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test {
    event TicketBought(address indexed buyer, uint256 ticketPrice);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 ticketPrice;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (ticketPrice, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link) =
            helperConfig.activeNetworkConfig();

        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    modifier passInterval() {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testRaffleInitializesInOpenState() external view {
        assert(raffle.s_raffleState() == Raffle.RaffleState.Open);
    }

    // buyTicket
    function testRevertsWhenEtherIsNotEnough() external {
        vm.expectRevert(Raffle.Raffle__NotEnoughEther.selector);
        raffle.buyTicket{value: ticketPrice - 1}();
    }

    function testBuyTicketRecordsPlayes() external {
        raffle.buyTicket{value: ticketPrice}();
        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testBuyTicketShouldEmitEvent() external {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit TicketBought(PLAYER, ticketPrice);
        raffle.buyTicket{value: ticketPrice}();
    }

    function testCantEnterWhenRaffleIsCalculating() external passInterval {
        raffle.buyTicket{value: ticketPrice}();
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);

        raffle.buyTicket{value: ticketPrice}();
    }

    //CheckUpkeep
    function testCheckUpkeepShouldReturnFalseIfNoBalance() external passInterval {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepShouldReturnFalseIfNoPlayers() external passInterval {
        vm.deal(address(raffle), STARTING_USER_BALANCE);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepShouldReturnFalseIfIntervalHasNotPassed() external {
        raffle.buyTicket{value: ticketPrice}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepShouldReturnFalseIfRaffleInCalculatingState() external passInterval {
        raffle.buyTicket{value: ticketPrice}();

        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepShouldReturnTrueIfAllConditionsAreMet() external passInterval {
        raffle.buyTicket{value: ticketPrice}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //PerformUpKeep
    function testPerformUpkeepShouldRevertIfCheckUpKeepIsRetunsFalse() external {
        vm.expectRevert(Raffle.Raffle__UpkeepNotNeeded.selector);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepShouldSetRaffleStateToCalculationg() external passInterval {
        raffle.buyTicket{value: ticketPrice}();

        raffle.performUpkeep("");
        Raffle.RaffleState state = raffle.s_raffleState();

        assert(state == Raffle.RaffleState.CalculatingWinner);
    }

    //fuzzing
    function testFulfillRandomWordsShouldOnlyBeCallableAfterPerformUpkeep(uint256 _requestId) external passInterval {
        raffle.buyTicket{value: ticketPrice}();

        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(_requestId, address(raffle));
    }

    function testFulfillRandomWordsShouldPickAWinner() external passInterval {
        uint8 numberOfPlayers = 5;

        raffle.buyTicket{value: ticketPrice}();

        for (uint256 i = 1; i <= numberOfPlayers; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.buyTicket{value: ticketPrice}();
        }

        uint256 prize = (numberOfPlayers + 1) * ticketPrice;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[2]; //

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        assert(uint256(raffle.s_raffleState()) == 0);
        assert(raffle.getLastWinner() != address(0));
        assert(raffle.getPlayers().length == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getLastWinner().balance == (STARTING_USER_BALANCE + prize) - ticketPrice);
    }
}
