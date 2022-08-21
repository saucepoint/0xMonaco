// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Car.sol";

contract ThePackage is Car {
    uint256 private lastBoost;
    uint256 private lastShell;

    enum GapType {
        Small,
        Medium,
        Large
    }

    uint256 private constant MAX_ACCELERATION = 5;
    uint256 private constant DENIMONATOR = 100;
    uint256 private constant EARLY_GAME = 300;
    uint256 private constant MID_GAME = 550;
    uint256 private constant MADMAX = 775;
    uint256 private constant ULTRAMAX = 900;
    uint256 private constant LIMITER = 14;

    constructor(Monaco _monaco) Car(_monaco) {}

    function randomNumbaBaby(Monaco.CarData memory ourCar, Monaco.CarData calldata opps1, Monaco.CarData calldata opps2) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            ourCar.balance, ourCar.speed, ourCar.y,
            opps1.balance, opps1.speed, opps1.y,
            opps2.balance, opps2.speed, opps2.y
        ))) % DENIMONATOR;
    }

    function boost(Monaco.CarData memory car, uint256 amount) private {
        uint256 cost = monaco.getAccelerateCost(amount);
        uint threshold;
        if (car.y < EARLY_GAME) {
            threshold = 18;
        } else if (car.y < MID_GAME) {
            threshold = 8;
        } else if (car.y < MADMAX) {
            threshold = 4;
        } else if (car.y < ULTRAMAX) {
            threshold = 2;
        } else {  // we are in the end game now
            threshold = 1;
        }
        if (cost <= (car.balance / threshold)) {
            monaco.buyAcceleration(amount);
        } else if (monaco.getAccelerateCost(amount / 2) <= (car.balance / threshold)) {
            monaco.buyAcceleration(amount / 2);
        } else if (monaco.getAccelerateCost(2) <= car.balance) {
            monaco.buyAcceleration(2);
        } else if (monaco.getAccelerateCost(1) <= car.balance) {
            monaco.buyAcceleration(1);
        }
    }

    function shell(Monaco.CarData memory car) private {
        uint256 cost = monaco.getShellCost(1);
        uint threshold;
        if (car.y < EARLY_GAME) {
            threshold = 25;
        } else if (car.y < MID_GAME) {
            threshold = 10;
        } else if (car.y < MADMAX) {
            threshold = 5;
        } else if (car.y < ULTRAMAX) {
            threshold = 3;
        } else {  // we are in the end game now
            threshold = 2;
        }
        if (cost <= (car.balance / threshold)) {
            monaco.buyShell(1);
        }
    }

    function takeYourTurn(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) external override {
        Monaco.CarData calldata car = allCars[ourCarIndex];

        // starting line
        if (car.y == 0) {
            boost(car, 1);
            return;
        }

        Monaco.CarData calldata firstCar = allCars[0];
        Monaco.CarData calldata secondCar = allCars[1];
        Monaco.CarData calldata thirdCar = allCars[2];

        uint256 rng = randomNumbaBaby(car, firstCar, secondCar);
        bool shelled;
        GapType gap = getGap(car, secondCar);
        GapType delta = getDelta(car, secondCar);
        GapType eco = getEco(car, secondCar, thirdCar);

        // if its free, fuggit
        if (monaco.getAccelerateCost(1) == 0) boost(car, 1);

        // if i'm in first place during early game, do nothing
        if (car.y < EARLY_GAME && ourCarIndex == 0 && rng < 30) {
            return;
        }

        // if we're in a mad max, burn the money
        if (ULTRAMAX <= car.y){
            if (eco != GapType.Medium) boost(car, 3);
            if (eco == GapType.Large) boost(car, 4);            
        } else if (MADMAX < car.y || MADMAX < firstCar.y || MADMAX < secondCar.y && (eco != GapType.Small)) {
            if (eco == GapType.Medium) boost(car, 2);
            if (eco == GapType.Large) boost(car, 3);
            if (ourCarIndex != 0 && monaco.getShellCost(1) < 100 && rng < 50 && 250 < car.balance) {
                shell(car);
            }
        }

        if (ourCarIndex == 0) {
            if (gap == GapType.Small && delta == GapType.Small) {
                // let them pass
            } else if (gap == GapType.Small && delta != GapType.Small) {
                drs(car, secondCar, 0, 0);  // maintain pace with them
            }
            else if (gap == GapType.Medium) {
                drs(car, secondCar, 0, 1);  // try to pull away
            } else if (gap == GapType.Medium && eco == GapType.Large) {
                drs(car, secondCar, 2, 2);  // got cash to burn
            }
        } else if (ourCarIndex == 1) {
            // got money to shell
            if (!shelled && (eco == GapType.Medium || eco == GapType.Large)) {
                shell(car);
                shelled = true;
            }
            if (getGap(car, firstCar) == GapType.Small) {
                drs(car, firstCar, 0, 0);
            } else if (getGap(car, firstCar) != GapType.Small) {
                shell(car);
                boost(car, 1);
            }
            else if (getGap(car, thirdCar) == GapType.Small && !shelled) {
                // shell(car);
            } else {
                boost(car, 1);
                if (rng < 30 && !shelled) {
                    shell(car);
                }
            }
        } else if (ourCarIndex == 2) {
            // got money to shell
            if (eco == GapType.Medium || eco == GapType.Large) {
                shell(car);
                shelled = true;
            }

            if (gap == GapType.Small) {
                drs(car, secondCar, 0, 0);
            } else if (gap == GapType.Medium) {
                drs(car, secondCar, 2, 1);
            } else {
                drs(car, secondCar, 3, 2);
            }
        }

        if (EARLY_GAME < car.y) excess_burn(car, ourCarIndex);
    }

    // ----------------------------------------------------------------------------------------------
    // Driving Modes
    // ----------------------------------------------------------------------------------------------
    function drs(Monaco.CarData calldata car, Monaco.CarData calldata opp, uint256 delta, uint256 fasterCase) private {
        bool imFaster = car.speed > opp.speed;
        uint256 deltaTarget = imFaster ? fasterCase : (opp.speed + delta - car.speed);
        if (0 < deltaTarget) {
            boost(car, deltaTarget);
        }
    }
    function excess_burn(Monaco.CarData calldata car, uint256 place) private {
        uint256 unitCost = 14;
        uint256 targetBal = 15000 - (car.y * unitCost);
        uint256 boostCost = monaco.getAccelerateCost(1);
        uint256 shellCost = monaco.getShellCost(1);
        bool boostCheaper = boostCost < shellCost ? true : false;
        if (targetBal < car.balance) {
            if (boostCost < unitCost && place == 0){
                boost(car, 1);
            } else if (boostCost < unitCost && boostCheaper) {
                boost(car, 1);
            } else if (shellCost < unitCost && place != 0) {
                shell(car);
            }
        }
    }

    // ----------------------------------------------------------------------------------------------
    // State
    // ----------------------------------------------------------------------------------------------
    function getGap(Monaco.CarData calldata car, Monaco.CarData calldata opp) private pure returns (GapType) {
        Monaco.CarData calldata lead = car.y < opp.y ? opp : car;
        Monaco.CarData calldata lag = car.y < opp.y ? car : opp;
        if (lead.y - lag.y < 15) {
            return GapType.Small;
        } else if (lead.y - lag.y < 35) {
            return GapType.Medium;
        } else {
            return GapType.Large;
        }
    }

    function getDelta(Monaco.CarData calldata car, Monaco.CarData calldata opp) private pure returns (GapType) {
        Monaco.CarData calldata lead = car.speed < opp.speed ? opp : car;
        Monaco.CarData calldata lag = car.speed < opp.speed ? car : opp;
        if (lead.speed - lag.speed <= 1) {
            return GapType.Small;
        } else if (lead.speed - lag.speed <= 4) {
            return GapType.Medium;
        } else {
            return GapType.Large;
        }
    }

    function getEco(Monaco.CarData calldata car, Monaco.CarData calldata opp1, Monaco.CarData calldata opp2) private pure returns (GapType) {
        uint256 avgEco = (opp1.balance + opp2.balance)/2;
        if (car.balance > ((opp1.balance + opp2.balance)*15)/10) {
            return GapType.Large;  // RICH
        } else if (car.balance  <= ((avgEco * 87) / 100)) {
            return GapType.Small; // POOR
        } else {
            return GapType.Medium;  // OK
        }
    }
}
