// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./cars/Car.sol";
import "./utils/SignedWadMath.sol";

import "solmate/utils/SafeCastLib.sol";

/// @title 0xMonaco: On-Chain Racing Game
/// @author transmissions11 <t11s@paradigm.xyz>
/// @author Bobby Abbott <bobby@paradigm.xyz>
/// @author Sina Sabet <sina@paradigm.xyz>
/// @dev Note: While 0xMonaco was originally written to be played as part
/// of the Paradigm CTF, it is not intended to have hidden vulnerabilities.
contract Monaco {
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TurnCompleted(uint256 indexed turn, CarData[] cars, uint256 acceleratePrice, uint256 shellPrice);

    event Shelled(uint256 indexed turn, Car indexed smoker, Car indexed smoked, uint256 amount, uint256 cost);

    event Accelerated(uint256 indexed turn, Car indexed car, uint256 amount, uint256 cost);

    event Registered(uint256 indexed turn, Car indexed car);

    event Punished(uint256 indexed turn, Car indexed car);

    event Rewarded(uint256 indexed turn, Car indexed car);

    event Dub(uint256 indexed turn, Car indexed winner);

    /*//////////////////////////////////////////////////////////////
                         MISCELLANEOUS CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint72 internal constant PLAYERS_REQUIRED = 3;

    uint32 internal constant POST_SHELL_SPEED = 1;

    uint32 internal constant STARTING_BALANCE = 15000;

    uint256 internal constant FINISH_DISTANCE = 1000;

    /*//////////////////////////////////////////////////////////////
                            PRICING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    int256 internal constant SHELL_TARGET_PRICE = 200e18;
    int256 internal constant SHELL_PER_TURN_DECREASE = 0.33e18;
    int256 internal constant SHELL_SELL_PER_TURN = 0.2e18;

    int256 internal constant ACCELERATE_TARGET_PRICE = 10e18;
    int256 internal constant ACCELERATE_PER_TURN_DECREASE = 0.33e18;
    int256 internal constant ACCELERATE_SELL_PER_TURN = 2e18;

    /*//////////////////////////////////////////////////////////////
                               GAME STATE
    //////////////////////////////////////////////////////////////*/

    enum State {
        WAITING,
        ACTIVE,
        DONE
    }

    State public state; // The current state of the game: pre-start, started, done.

    uint16 public turns = 1; // Number of turns played since the game started.

    uint72 public entropy; // Random data used to choose the next turn.

    Car public currentCar; // The car currently making a move.

    /*//////////////////////////////////////////////////////////////
                               SALES STATE
    //////////////////////////////////////////////////////////////*/

    enum ActionType {
        ACCELERATE,
        SHELL
    }

    mapping(ActionType => uint256) public getActionsSold;

    /*//////////////////////////////////////////////////////////////
                               CAR STORAGE
    //////////////////////////////////////////////////////////////*/

    struct CarData {
        uint32 balance; // Where 0 means the car has no money.
        uint32 speed; // Where 0 means the car isn't moving.
        uint32 y; // Where 0 means the car hasn't moved.
        Car car;
    }

    Car[] public cars;

    mapping(Car => CarData) public getCarData;

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function register(Car car) external {
        // Prevent accidentally or intentionally registering a car multiple times.
        require(address(getCarData[car].car) == address(0), "DOUBLE_REGISTER");

        // Register the caller as a car in the race.
        getCarData[car] = CarData({balance: STARTING_BALANCE, car: car, speed: 0, y: 0});

        cars.push(car); // Append to the list of cars.

        // Retrieve and cache the total number of cars.
        uint256 totalCars = cars.length;

        // If the game is now full, kick things off.
        if (totalCars == PLAYERS_REQUIRED) {
            // Use the timestamp as random input.
            entropy = uint72(block.timestamp);

            // Mark the game as active.
            state = State.ACTIVE;
        } else require(totalCars < PLAYERS_REQUIRED, "MAX_PLAYERS");

        emit Registered(0, car);
    }

    /*//////////////////////////////////////////////////////////////
                                CORE GAME
    //////////////////////////////////////////////////////////////*/

    function play(uint256 turnsToPlay) external onlyDuringActiveGame {
        unchecked {
            // We'll play turnsToPlay turns, or until the game is done.
            for (; turnsToPlay != 0; turnsToPlay--) {
                Car[] memory allCars = cars; // Get and cache the cars.

                uint256 currentTurn = turns; // Get and cache the current turn.

                // Get the current car by moduloing the turns variable by the player count.
                Car currentTurnCar = allCars[currentTurn % PLAYERS_REQUIRED];

                // Get all car data and the current turn car's index so we can pass it via takeYourTurn.
                (CarData[] memory allCarData, uint256 yourCarIndex) = getAllCarDataAndFindCar(currentTurnCar);

                currentCar = currentTurnCar; // Set the current car temporarily.

                // Call the car to have it take its turn with a max of 2 million gas, and catch any errors that occur.
                try currentTurnCar.takeYourTurn{gas: 2_000_000}(allCarData, yourCarIndex) {} catch {}

                delete currentCar; // Restore the current car to the zero address.

                // Loop over all of the cars and update their data.
                for (uint256 i = 0; i < PLAYERS_REQUIRED; i++) {
                    Car car = allCars[i]; // Get the car.

                    // Get a pointer to the car's data struct.
                    CarData storage carData = getCarData[car];

                    // If the car is now past the finish line after moving:
                    if ((carData.y += carData.speed) >= FINISH_DISTANCE) {
                        emit Dub(currentTurn, car); // It won.

                        state = State.DONE;

                        return; // Exit early.
                    }
                }

                // If this is the last turn in the batch:
                if (currentTurn % PLAYERS_REQUIRED == 0) {
                    // Knuth shuffle over the cars using our entropy as randomness.
                    for (uint256 j = 0; j < PLAYERS_REQUIRED; ++j) {
                        // Generate a new random number by hashing the old one.
                        uint256 newEntropy = (entropy = uint72(uint256(keccak256(abi.encode(entropy)))));

                        // Choose a random position in front of j to swap with..
                        uint256 j2 = j + (newEntropy % (PLAYERS_REQUIRED - j));

                        Car temp = allCars[j];
                        allCars[j] = allCars[j2];
                        allCars[j2] = temp;
                    }

                    cars = allCars; // Reorder cars using the new shuffled ones.
                }

                // Note: If we were to deploy this on-chain it this line in particular would be pretty wasteful gas-wise.
                emit TurnCompleted(turns = uint16(currentTurn + 1), getAllCarData(), getAccelerateCost(1), getShellCost(1));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    function buyAcceleration(uint256 amount) external onlyDuringActiveGame onlyCurrentCar returns (uint256 cost) {
        cost = getAccelerateCost(amount); // Get the cost of the acceleration.

        // Get a storage pointer to the calling car's data struct.
        CarData storage car = getCarData[Car(msg.sender)];

        car.balance -= cost.safeCastTo32(); // This will underflow if we cant afford.

        unchecked {
            car.speed += uint32(amount); // Increase their speed by the amount.

            // Increase the number of accelerates sold.
            getActionsSold[ActionType.ACCELERATE] += amount;
        }

        emit Accelerated(turns, Car(msg.sender), amount, cost);
    }

    function buyShell(uint256 amount) external onlyDuringActiveGame onlyCurrentCar returns (uint256 cost) {
        require(amount != 0, "YOU_CANT_BUY_ZERO_SHELLS"); // Buying zero shells would make them free.

        cost = getShellCost(amount); // Get the cost of the shells.

        // Get a storage pointer to the calling car's data struct.
        CarData storage car = getCarData[Car(msg.sender)];

        car.balance -= cost.safeCastTo32(); // This will underflow if we cant afford.

        uint256 y = car.y; // Retrieve and cache the car's y.

        unchecked {
            // Increase the number of shells sold.
            getActionsSold[ActionType.SHELL] += amount;

            Car closestCar; // Used to determine who to shell.
            uint256 distanceFromClosestCar = type(uint256).max;

            for (uint256 i = 0; i < PLAYERS_REQUIRED; i++) {
                CarData memory nextCar = getCarData[cars[i]];

                // If the car is behind or on us, skip it.
                if (nextCar.y <= y) continue;

                // Measure the distance from the car to us.
                uint256 distanceFromNextCar = nextCar.y - y;

                // If this car is closer than all other cars we've
                // looked at so far, we'll make it the closest one.
                if (distanceFromNextCar < distanceFromClosestCar) {
                    closestCar = nextCar.car;
                    distanceFromClosestCar = distanceFromNextCar;
                }
            }

            // If there is a closest car, shell it.
            if (address(closestCar) != address(0)) {
                // Set the speed to POST_SHELL_SPEED unless its already at that speed or below, as to not speed it up.
                if (getCarData[closestCar].speed > POST_SHELL_SPEED) getCarData[closestCar].speed = POST_SHELL_SPEED;
            }

            emit Shelled(turns, Car(msg.sender), closestCar, amount, cost);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ACTION PRICING
    //////////////////////////////////////////////////////////////*/

    function getAccelerateCost(uint256 amount) public view returns (uint256 sum) {
        unchecked {
            for (uint256 i = 0; i < amount; i++) {
                sum += computeActionPrice(
                    ACCELERATE_TARGET_PRICE,
                    ACCELERATE_PER_TURN_DECREASE,
                    turns,
                    getActionsSold[ActionType.ACCELERATE] + i,
                    ACCELERATE_SELL_PER_TURN
                );
            }
        }
    }

    function getShellCost(uint256 amount) public view returns (uint256 sum) {
        unchecked {
            for (uint256 i = 0; i < amount; i++) {
                sum += computeActionPrice(
                    SHELL_TARGET_PRICE,
                    SHELL_PER_TURN_DECREASE,
                    turns,
                    getActionsSold[ActionType.SHELL] + i,
                    SHELL_SELL_PER_TURN
                );
            }
        }
    }

    function computeActionPrice(
        int256 targetPrice,
        int256 perTurnPriceDecrease,
        uint256 turnsSinceStart,
        uint256 sold,
        int256 sellPerTurnWad
    ) internal pure returns (uint256) {
        unchecked {
            // prettier-ignore
            return uint256(
                wadMul(targetPrice, wadExp(unsafeWadMul(wadLn(1e18 - perTurnPriceDecrease),
                // Theoretically calling toWadUnsafe with turnsSinceStart and sold can overflow without
                // detection, but under any reasonable circumstance they will never be large enough.
                // Use sold + 1 as we need the number of the tokens that will be sold (inclusive).
                // Use turnsSinceStart - 1 since turns start at 1 but here the first turn should be 0.
                toWadUnsafe(turnsSinceStart - 1) - (wadDiv(toWadUnsafe(sold + 1), sellPerTurnWad))
            )))) / 1e18;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyDuringActiveGame() {
        require(state == State.ACTIVE, "GAME_NOT_ACTIVE");

        _;
    }

    modifier onlyCurrentCar() {
        require(Car(msg.sender) == currentCar, "NOT_CURRENT_CAR");

        _;
    }

    function getAllCarData() public view returns (CarData[] memory results) {
        results = new CarData[](PLAYERS_REQUIRED); // Allocate the array.

        // Get a list of cars sorted descendingly by y.
        Car[] memory sortedCars = getCarsSortedByY();

        unchecked {
            // Copy over each car's data into the results array.
            for (uint256 i = 0; i < PLAYERS_REQUIRED; i++) results[i] = getCarData[sortedCars[i]];
        }
    }

    function getAllCarDataAndFindCar(Car carToFind) public view returns (CarData[] memory results, uint256 foundCarIndex) {
        results = new CarData[](PLAYERS_REQUIRED); // Allocate the array.

        // Get a list of cars sorted descendingly by y.
        Car[] memory sortedCars = getCarsSortedByY();

        unchecked {
            // Copy over each car's data into the results array.
            for (uint256 i = 0; i < PLAYERS_REQUIRED; i++) {
                Car car = sortedCars[i];

                // Once we find the car, we can set the index.
                if (car == carToFind) foundCarIndex = i;

                results[i] = getCarData[car];
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              SORTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function getCarsSortedByY() internal view returns (Car[] memory sortedCars) {
        unchecked {
            sortedCars = cars; // Initialize sortedCars.

            // Implements a descending bubble sort algorithm.
            for (uint256 i = 0; i < PLAYERS_REQUIRED; i++) {
                for (uint256 j = i + 1; j < PLAYERS_REQUIRED; j++) {
                    // Sort cars descendingly by their y position.
                    if (getCarData[sortedCars[j]].y > getCarData[sortedCars[i]].y) {
                        Car temp = sortedCars[i];
                        sortedCars[i] = sortedCars[j];
                        sortedCars[j] = temp;
                    }
                }
            }
        }
    }
}
