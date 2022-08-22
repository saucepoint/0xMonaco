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

    // maximum accelerants to buy, if we engage max bidding
    uint256 private constant MAX_BID = 6;

    // maximum accelerants to buy for a given turn
    uint256 private constant MAX_DELTA = 16;
    
    // when different race phases start i.e. engage "flat out mode" after y=860
    uint256 private constant MID_GAME = 450;  // pretty much do nothing up until this point
    uint256 private constant MADMAX = 770;
    uint256 private constant FLATOUT = 855;  // go all out, try to spend the funds

    // threshold for determining if theres a speed demon behind us
    uint256 private constant LAGGING_SPEED_DEMON = 16;
    
    // if car in front has a speed higher than this, hit them with the "dont"
    uint256 private constant LIMITER = 18;

    // if car in front has a delta higher than this, hit them with the "dont"
    uint256 private constant DELTA_LIMITER = 8;

    uint256 private constant DENIMONATOR = 100;

    constructor(Monaco _monaco) Car(_monaco) {}

    // pseudo-random number generator, because i dont trust myself with decisions
    function randomNumbaBaby(Monaco.CarData memory ourCar, Monaco.CarData calldata opps1, Monaco.CarData calldata opps2) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            ourCar.balance, ourCar.speed, ourCar.y,
            opps1.balance, opps1.speed, opps1.y,
            opps2.balance, opps2.speed, opps2.y
        ))) % DENIMONATOR;
    }

    // Wraps monaco.buyAcceleration() with some economy checks
    function boost(Monaco.CarData memory car, uint256 _amount) private {
        // no need to spend monies on early game speed
        if (car.y < 300 && 7 <= car.speed) return;
        if (MID_GAME <= car.y && car.y < MADMAX && 26 <= car.speed) return;
        
        // max limit how much accelerant to buy
        uint256 amount = _amount < MAX_DELTA ? _amount : MAX_DELTA;
        
        // sets the budget -- the fraction of cash.balance we're allowed to spend
        // i.e. in the early game, do not spend more than 1/20th of our balance
        uint threshold;
        if (car.y < MID_GAME) {
            threshold = 20;
        } else if (MID_GAME <= car.y && car.y < MADMAX) {
            threshold = 10;
        } else if (MADMAX <= car.y && car.y < FLATOUT) {
            // if theres some excess cash, fuggit allow a higher spend
            threshold = (2400 < car.balance) ? 4 : 5;
        } else if (FLATOUT <= car.y) {
            // if theres some excess cash, fuggit allow a higher spend
            threshold = (2400 < car.balance) ? 1 : 2;
        } else {
            threshold = 4;
        }

        // loop to find the amount of accelerant thats within our budget
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

        // if we didnt boost, but there was a request to boost
        // honor the request if the amount is less than 66% of the balance
        if (!boosted && monaco.getAccelerateCost(1) <= (car.balance * 66)/100) monaco.buyAcceleration(1);
    }

    // Wraps monaco.buyAcceleration() with some economy checks
    function shell(Monaco.CarData memory car) private {
        uint256 cost = monaco.getShellCost(1);
        
        // similar to boost(), we set a budget based on our positioning on the track
        uint threshold;
        if (car.y <= 75) {
            threshold = 8;
        } else if (car.y < MID_GAME) {
            threshold = 20;
        } else if  (MID_GAME <= car.y && car.y < MADMAX) {
            threshold = 12;
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

    // Determines if the opponent (in front) is going too fast
    // if so, stop 'em
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
        if (car.y <= 1) {
            boost(car, 3);
            return;
        }

        // record the actions, which is applied at the very end
        uint256 boostCounter;
        bool toShell;
        bool oppMustBeStopped;

        // determine our economy compared to other cars
        GapType eco = getEco(car, allCars[1], allCars[2]);

        // market dependent boosting
        // i.e. if max bidding is cheap, do it
        //      or if boosts are cheap, just buy them
        if (MID_GAME < car.y)
            boostCounter += max_bid(car);

        // if opps is really fast, stop them
        if (ourCarIndex != 0)
            oppMustBeStopped = oppStopper(car, allCars[ourCarIndex - 1]);

        // if we're slow at the end, try to rev the engines back up
        if (MADMAX <= car.y && car.speed <= 2) {
            boostCounter += 6;
        }

        // if i'm in first place during early game, do nothing
        if (car.y < MID_GAME && ourCarIndex == 0 && randomNumbaBaby(car, allCars[0], allCars[1]) < 50) {
            return;
        } else if (car.y < MID_GAME && 8 < car.speed) {
            return;
        }

        // if we're in late game, burn the money
        if (FLATOUT <= car.y){
            if (eco == GapType.Small) boostCounter += 3;
            else if (eco == GapType.Medium) boostCounter += 4;
            else if (eco == GapType.Large) boostCounter += 6;
        } else if (MADMAX < allCars[0].y || MADMAX < allCars[1].y || MADMAX < allCars[2].y) {
            if (eco == GapType.Small) boostCounter += 1;
            else if (eco == GapType.Medium) boostCounter += 2;
            else if (eco == GapType.Large) boostCounter += 6;
        }

        // if we're in late game and its cheap to shell, might as well do it
        if (MADMAX < car.y && ourCarIndex != 0) {
            toShell = toShell || madMaxShelling(car, allCars[ourCarIndex - 1]);
        }

        // main game logic, decide what to do based on position
        uint256 _boost;
        bool _shell;
        (_boost, _shell) = decision(
            ourCarIndex, car,
            allCars[0], allCars[1], allCars[2], eco
        );
        boostCounter += _boost;
        toShell = toShell || _shell;

        // if we're surplus cash, relative our position, spend it
        (_boost, _shell) = checkBurn(ourCarIndex, car, toShell);
        boostCounter += _boost;
        toShell = toShell || _shell;

        // if we're in the late game, and opps cannot afford shells, then boost
        if (MADMAX <= car.y) {
            (_boost) = safeBoost(allCars, ourCarIndex);
            boostCounter += _boost;
        }
        
        // check for a speed demon in the rear view mirror!
        // if so, we'll hold off shelling until the next turn
        uint256 lagSpeed;
        if (ourCarIndex == 0) {
            lagSpeed = allCars[1].speed < allCars[2].speed ? allCars[2].speed : allCars[1].speed;
        } else if (ourCarIndex == 1) {
            lagSpeed = allCars[2].speed;
        }
        
        // apply actions
        // if theres someone behind us & theyre going fast, save the shell instead
        if (toShell && lagSpeed < LAGGING_SPEED_DEMON) shell(car);
        else if (oppMustBeStopped) shell(car);
        
        if (0 < boostCounter) boost(car, boostCounter);
    }

    // ----------------------------------------------------------------------------------------------
    // Main Generic Decision Tree
    // ----------------------------------------------------------------------------------------------
    function decision(
        uint256 ourCarIndex, Monaco.CarData calldata car, Monaco.CarData calldata firstCar, Monaco.CarData calldata secondCar, Monaco.CarData calldata thirdCar,
        GapType eco
    ) private pure returns (uint256 moreBoost, bool toShell) {
        GapType gap = getGap(car, secondCar);
        GapType delta = getDelta(car, secondCar);
        uint256 rng = randomNumbaBaby(car, firstCar, secondCar);
        if (ourCarIndex == 0) {
            if (car.y < 600) {
                // sandbag & do nothing
            } else if (car.y < MADMAX && gap == GapType.Medium && delta == GapType.Small) {
                // let them pass if its early
                if (car.speed < 2) moreBoost += 1;
            } else if (gap == GapType.Large && getGap(secondCar, thirdCar) == GapType.Small) {
                moreBoost += drs(car, secondCar, 1, 2);  // pull away when 2nd and 3rd are battling
            } else if (gap == GapType.Small && delta != GapType.Small) {
                moreBoost += drs(car, secondCar, 0, 0);  // maintain pace with them
            } else if (gap == GapType.Medium && MADMAX <= car.y) {
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
            if (car.y < MID_GAME) {
                moreBoost += 1;
            } else if (car.y < 650) {
                moreBoost += 2;
            } else if (gap == GapType.Small) {
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

    // spends surplus cash
    function checkBurn(uint256 ourCarIndex, Monaco.CarData calldata car, bool toShell) private view returns (uint256 _moreBoost, bool _toShell) {
        if (MID_GAME < car.y && car.y < MADMAX)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 1, toShell);
        else if (MADMAX <= car.y && car.y < FLATOUT)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 2, toShell);
        else if (FLATOUT <= car.y)
            (_moreBoost, _toShell) = excess_burn(car, ourCarIndex, 2, toShell);
    }

    // buy extra boost if opps cannot afford shells
    function safeBoost(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) private view returns (uint256 _moreBoost) {
        uint256 opps1Balance;
        uint256 opps2Balance;
        if (ourCarIndex == 0) {
            opps1Balance = allCars[1].balance;
            opps2Balance = allCars[2].balance;
        } else if (ourCarIndex == 1) {
            opps1Balance = allCars[0].balance;
            opps2Balance = allCars[2].balance;
        } else if (ourCarIndex == 2) {
            opps1Balance = allCars[0].balance;
            opps2Balance = allCars[1].balance;
        }
        uint256 shellCost = monaco.getShellCost(1);
        if (opps1Balance < shellCost || opps2Balance < shellCost) {
            _moreBoost = 2;
        }
    }

    // random shelling at the end of the game
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
    // calculates how much accelerant we need, relative to an opponents car
    // i.e. we can maintain speed, or add keep a positive delta over the opps
    function drs(Monaco.CarData calldata car, Monaco.CarData calldata opp, uint256 delta, uint256 fasterCase) private pure returns (uint256 moreBoost) {
        moreBoost = (opp.speed < car.speed) ? fasterCase : (opp.speed + delta - car.speed);
    }

    // determines if theres excess cash to spend
    function excess_burn(Monaco.CarData calldata car, uint256 place, uint256 multiplier, bool shelled) private view returns (uint256 moreBoost, bool toShell) {
        uint256 unitCost = 13;  // assumes the cost of an action unit is 13; should be 15 (15 units per 1000 distance units = 15,000 cash)

        // using 15000 here means we are targetting an exact balance=0 at y=1000
        // pad it a bit, so that we end the race with 1500 cash
        uint256 targetBal = 16500 - (car.y * unitCost);
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

    // max bidding / buying cheap boosts
    function max_bid(Monaco.CarData calldata car) private returns (uint256 moreBoost) {
        // if its cheap, fuggit
        uint256 maxBid = monaco.getAccelerateCost(MAX_BID);
        uint256 _lastBid = (lastMaxBid * 85) / 100;
        if (MID_GAME < car.y && (maxBid < _lastBid)) moreBoost = MAX_BID;
        else if (monaco.getAccelerateCost(1) <= 8) moreBoost = 1;
        lastMaxBid = maxBid;
    }

    // ----------------------------------------------------------------------------------------------
    // State comparisons. Get data in relation to other cars
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
