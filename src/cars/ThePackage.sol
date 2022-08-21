// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Car.sol";

contract ThePackage is Car {
    uint256 private lastMaxBid;
    enum GapType {
        Small,
        Medium,
        Large
    }

    uint256 private constant MAX_BID = 5;
    uint256 private constant MAX_DELTA = 14;
    uint256 private constant DENIMONATOR = 100;
    // when different race phases START. i.e. engage flat out after y=860
    uint256 private constant MID_GAME = 420;
    uint256 private constant MADMAX = 740;
    uint256 private constant FLATOUT = 860;
    uint256 private constant LIMITER = 20;
    uint256 private constant DELTA_LIMITER = 8;

    constructor(Monaco _monaco) Car(_monaco) {}

    function randomNumbaBaby(Monaco.CarData memory ourCar, Monaco.CarData calldata opps1, Monaco.CarData calldata opps2) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            ourCar.balance, ourCar.speed, ourCar.y,
            opps1.balance, opps1.speed, opps1.y,
            opps2.balance, opps2.speed, opps2.y
        ))) % DENIMONATOR;
    }

    function boost(Monaco.CarData memory car, uint256 _amount) private {
        if (car.y < MID_GAME && 9 <= car.speed) return;
        if (MID_GAME <= car.y && car.y < MADMAX && 20 <= car.speed) return;
        
        uint256 amount = _amount < MAX_DELTA ? _amount : MAX_DELTA;
        uint threshold;
        if (car.y < MID_GAME) {
            threshold = 20;
        } else if (MID_GAME <= car.y && car.y < MADMAX) {
            threshold = 15;
        } else if (MADMAX <= car.y && car.y < FLATOUT) {
            threshold = (2200 < car.balance) ? 4 : 5;
        } else if (FLATOUT <= car.y) {
            threshold = (2200 < car.balance) ? 1 : 2;
        } else {
            threshold = 4;
        }
        uint256 i;
        uint256 boostToBuy;
        bool boosted;
        for (i; i < MAX_DELTA; i++) {
            boostToBuy = amount - i;
            if (monaco.getAccelerateCost(boostToBuy) < (car.balance / threshold)){
                monaco.buyAcceleration(boostToBuy);
                boosted = true;
                break;
            }
        }
        if (!boosted && monaco.getAccelerateCost(1) <= (car.balance * 66)/100) monaco.buyAcceleration(1);
    }

    function shell(Monaco.CarData memory car) private {
        uint256 cost = monaco.getShellCost(1);
        uint threshold;
        if (car.y <= 75) {
            threshold = 8;
        } else if (car.y < MID_GAME) {
            threshold = 25;
        } else if  (MID_GAME <= car.y && car.y < MADMAX) {
            threshold = 15;
        } else if (MADMAX <= car.y && car.y < FLATOUT && 2000 < car.balance) {
            threshold = 2;
        } else if (MADMAX <= car.y && car.y < FLATOUT) {
            threshold = 3;
        } else if (FLATOUT <= car.y) {
            threshold = 1;
        } else {
            threshold = 1;
        }
        if (cost <= (car.balance / threshold)) {
            monaco.buyShell(1);
        }
    }

    function oppStopper(Monaco.CarData calldata car, Monaco.CarData calldata opps) private pure returns (bool) {
        if (LIMITER <= opps.speed
            || (getGap(car, opps) == GapType.Large)
            || (getGap(car, opps) == GapType.Medium && MADMAX <= car.y)
        ) {
           return true;
        } else if ((car.speed < opps.speed) && (DELTA_LIMITER < (opps.speed - car.speed))) {
            return true;
        } else {
            return false;
        }
    }

    function takeYourTurn(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) external override {
        Monaco.CarData calldata car = allCars[ourCarIndex];

        // starting line
        if (car.y <= 2) {
            boost(car, 4);
            return;
        }

        uint256 boostCounter;
        bool toShell;
        GapType gap = getGap(car, allCars[1]);
        GapType delta = getDelta(car, allCars[1]);
        GapType eco = getEco(car, allCars[1], allCars[2]);

        // market dependent boosting
        boostCounter += max_bid(car);

        // if opps is really fast, stop them
        if (ourCarIndex != 0)
            toShell = oppStopper(car, allCars[ourCarIndex - 1]);

        // if we're slow at the end, try to rev the engines
        if (MADMAX <= car.y && car.speed <= 2) {
            boostCounter += 6;
        }

        // if i'm in first place during early game, do nothing
        if (car.y < MID_GAME && ourCarIndex == 0 && randomNumbaBaby(car, allCars[0], allCars[1]) < 50) {
            return;
        } else if (car.y < MID_GAME && 8 < car.speed) {
            return;
        }

        // if we're in a mad max, burn the money
        if (FLATOUT <= car.y){
            if (eco == GapType.Small) boostCounter += 3;
            else if (eco == GapType.Medium) boostCounter += 4;
            else if (eco == GapType.Large) boostCounter += 6;
        } else if (MADMAX < car.y || MADMAX < allCars[1].y) {
            if (eco == GapType.Small) boostCounter += 0;
            else if (eco == GapType.Medium) boostCounter += 2;
            else if (eco == GapType.Large) boostCounter += 2;
        }

        if (MADMAX < car.y && ourCarIndex != 0) {
            toShell = toShell || madMaxShelling(car, allCars[ourCarIndex - 1]);
        }

        uint256 _boost;
        bool _shell;
        (_boost, _shell) = decision(
            ourCarIndex, car,
            allCars[0], allCars[1], allCars[2],
            gap, eco, delta
        );
        boostCounter += _boost;
        toShell = toShell || _shell;

        (_boost, _shell) = checkBurn(ourCarIndex, car, toShell);
        boostCounter += _boost;
        toShell = toShell || _shell;

        (_boost) = safeBoost(allCars, ourCarIndex);
        boostCounter += _boost;
        
        // apply actions
        if (toShell) shell(car);
        if (0 < boostCounter) boost(car, boostCounter);
    }

    // ----------------------------------------------------------------------------------------------
    // Main Generic Decision Tree
    // ----------------------------------------------------------------------------------------------
    function decision(
        uint256 ourCarIndex, Monaco.CarData calldata car, Monaco.CarData calldata firstCar, Monaco.CarData calldata secondCar, Monaco.CarData calldata thirdCar,
        GapType gap, GapType eco, GapType delta
    ) private pure returns (uint256 moreBoost, bool toShell) {
        uint256 rng = randomNumbaBaby(car, firstCar, secondCar);
        if (ourCarIndex == 0) {
            if (car.y < MADMAX && gap == GapType.Small && delta == GapType.Small) {
                // let them pass if its early
                if (car.speed < 2) moreBoost += 1;
            } else if (gap == GapType.Large && getGap(secondCar, thirdCar) == GapType.Small) {
                moreBoost += drs(car, secondCar, 2, 2);  // pull away when 2nd and 3rd are battling
            } else if (gap == GapType.Small && delta != GapType.Small) {
                moreBoost += drs(car, secondCar, 0, 0);  // maintain pace with them
            } else if (gap == GapType.Medium) {
                moreBoost += drs(car, secondCar, 1, 0);  // try to pull away
            } else if (gap == GapType.Medium && eco == GapType.Large) {
                moreBoost += drs(car, secondCar, 2, 2);  // got cash to burn
            } else if (gap == GapType.Large) {
                moreBoost += drs(car, secondCar, 1, 1);
            } else {
                moreBoost += drs(car, secondCar, 0, 0);
            }
        } else if (ourCarIndex == 1) {
            // got money to shell
            if (eco == GapType.Large
                || getDelta(car, firstCar) == GapType.Large
            ) {
                toShell = true;
            }
            if (getGap(car, firstCar) == GapType.Small) {
                if (FLATOUT <= car.y)
                    moreBoost += drs(car, firstCar, 2, 1);
                if (FLATOUT > car.y)
                    moreBoost += drs(car, firstCar, 0, 0);
            } else if (MID_GAME < car.y && getGap(car, firstCar) != GapType.Small) {
                uint256 _delta = toShell ? 1 : 2;
                uint256 _diff = toShell ? 0 : 1;
                moreBoost += drs(car, firstCar, _delta, _diff);
                if (getDelta(car, firstCar) != GapType.Small ) toShell = true;
            }
            else if (getGap(car, thirdCar) == GapType.Small) {
                // let them pass
            } else if (MID_GAME < car.y){
                if (FLATOUT <= car.y)
                    moreBoost += drs(car, firstCar, 2, 2);
                if (FLATOUT > car.y)
                    moreBoost += drs(car, firstCar, 1, 0);
                if (rng < 50 && !toShell) {
                    toShell = true;
                }
            }
        } else if (ourCarIndex == 2) {
            // got money to shell
            if (eco == GapType.Medium || eco == GapType.Large) {
                toShell = true;
            }

            if (gap == GapType.Small) {
                if (MADMAX <= car.y && car.y < FLATOUT)
                    moreBoost += drs(car, secondCar, 0, 0);
                if (FLATOUT <= car.y)
                    moreBoost += drs(car, secondCar, 2, 2);
            } else if (gap == GapType.Medium) {
                moreBoost += drs(car, secondCar, 2, 0);
            } else {
                moreBoost += drs(car, secondCar, 3, 3);
            }
        }
    }

    function checkBurn(uint256 ourCarIndex, Monaco.CarData calldata car, bool toShell) private view returns (uint256 _moreBoost, bool _toShell) {
        if (MID_GAME < car.y && car.y < MADMAX)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 1, toShell);
        else if (MADMAX <= car.y && car.y < FLATOUT)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 2, toShell);
        else if (FLATOUT <= car.y)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 2, toShell);
    }

    function safeBoost(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) private view returns (uint256 _moreBoost) {
        uint256 opps1Balance;
        uint256 opps2Balance;
        if (ourCarIndex == 0) {
            opps1Balance = allCars[1].y;
            opps2Balance = allCars[2].y;
        } else if (ourCarIndex == 1) {
            opps1Balance = allCars[0].y;
            opps2Balance = allCars[2].y;
        } else if (ourCarIndex == 2) {
            opps1Balance = allCars[0].y;
            opps2Balance = allCars[1].y;
        }
        uint256 shellCost = monaco.getShellCost(1);
        if (opps1Balance < shellCost && opps2Balance < shellCost) {
            _moreBoost = 2;
        }
    }

    function madMaxShelling(Monaco.CarData calldata car, Monaco.CarData calldata opps) private view returns (bool) {
        uint256 rng = randomNumbaBaby(car, opps, car);
        if (monaco.getShellCost(1) < 100 && rng < 65) {
            return true;
        } else if (8 < opps.speed && rng < 65) {
            return true;
        } else {
            return false;
        }
    }

    // ----------------------------------------------------------------------------------------------
    // Driving Modes
    // ----------------------------------------------------------------------------------------------
    function drs(Monaco.CarData calldata car, Monaco.CarData calldata opp, uint256 delta, uint256 fasterCase) private pure returns (uint256 moreBoost) {
        moreBoost = (opp.speed < car.speed) ? fasterCase : (opp.speed + delta - car.speed);
    }
    function excess_burn(Monaco.CarData calldata car, uint256 place, uint256 multiplier, bool shelled) private view returns (uint256 moreBoost, bool toShell) {
        uint256 unitCost = 12;
        uint256 targetBal = 16400 - (car.y * unitCost);
        uint256 boostCost = monaco.getAccelerateCost(multiplier);
        uint256 shellCost = monaco.getShellCost(1);
        bool boostCheaper = boostCost < shellCost ? true : false;
        if (targetBal < car.balance) {
            if (place == 0 || boostCheaper) {
                moreBoost = multiplier;
            } else if (place != 0 && !shelled) {
                toShell = true;
            } else {
                moreBoost = multiplier;
            }
        }
    }
    function max_bid(Monaco.CarData calldata car) private returns (uint256 moreBoost) {
        // if its cheap, fuggit
        uint256 maxBid = monaco.getAccelerateCost(MAX_BID);
        uint256 _lastBid = (lastMaxBid * 90) / 100;
        if (MID_GAME < car.y && (maxBid < _lastBid)) moreBoost = MAX_BID;
        else if (monaco.getAccelerateCost(1) <= 8) moreBoost = 1;
        lastMaxBid = maxBid;
    }

    // ----------------------------------------------------------------------------------------------
    // State
    // ----------------------------------------------------------------------------------------------
    function getGap(Monaco.CarData calldata car, Monaco.CarData calldata opp) private pure returns (GapType) {
        Monaco.CarData calldata lead = car.y < opp.y ? opp : car;
        Monaco.CarData calldata lag = car.y < opp.y ? car : opp;
        if (lead.y - lag.y < 15) {
            return GapType.Small;
        } else if (lead.y - lag.y < 40) {
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
        if (car.balance > ((avgEco*15)/10)) {
            return GapType.Large;  // RICH
        } else if (car.balance  <= ((avgEco * 87) / 100)) {
            return GapType.Small; // POOR
        } else {
            return GapType.Medium;  // OK
        }
    }
}
