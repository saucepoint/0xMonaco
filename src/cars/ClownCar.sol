// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Car.sol";

contract ClownCar is Car {

    uint256 private lastBoost;
    uint256 private lastShell;
    uint256 private constant COINFLIP = 3;
    uint256 private constant MAX_ACCELERATION = 5;
    uint256 private constant DENIMONATOR = 100;
    uint256 private constant MADMAX = 700;

    constructor(Monaco _monaco) Car(_monaco) {}

    function randomNumbaBaby(Monaco.CarData memory ourCar, Monaco.CarData calldata opps1, Monaco.CarData calldata opps2, uint256 m) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            ourCar.balance, ourCar.speed, ourCar.y,
            opps1.balance, opps1.speed, opps1.y,
            opps2.balance, opps2.speed, opps2.y
        ))) % m;
    }

    function takeYourTurn(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) external override {
        Monaco.CarData memory ourCar = allCars[ourCarIndex];
        uint256 opps1Index;
        uint256 opps2Index;
        if (ourCarIndex == 0) {
            opps1Index = 1;
            opps2Index = 2;
        } else if (ourCarIndex == 1) {
            opps1Index = 0;
            opps2Index = 2;
        } else {
            opps1Index = 0;
            opps2Index = 1;
        }
        bool shelled;
        bool lowCash = ourCar.balance < 3000 && ourCar.balance <= allCars[opps1Index].balance && ourCar.balance <= allCars[opps2Index].balance;

        uint256 shellCost = monaco.getShellCost(1);
        uint256 boostCost = monaco.getAccelerateCost(1);

        // if we're the fastest on the track, buy 1 boost
        if (ourCar.speed > allCars[opps1Index].speed && ourCar.speed > allCars[opps2Index].speed) {
            if (boostCost <= ourCar.balance) {
                monaco.buyAcceleration(1);
            }
            return;
        }

        // Primary Logic:
        // DRS: if we have double of the combined cash & the cost of MAX BID is less than half of it, lets BOOST
        bool rich = ourCar.balance >= (allCars[opps1Index].balance + allCars[opps2Index].balance) * 2;
        if (rich && monaco.getAccelerateCost(MAX_ACCELERATION) <= ourCar.balance / 2) {
            monaco.buyAcceleration(MAX_ACCELERATION);
            return;
        }

        // if we're getting gapped, buy a shell & boost
        if (ourCarIndex != 0 && ourCar.speed < allCars[ourCarIndex - 1].speed) {
            if ((allCars[ourCarIndex-1].y - ourCar.y) > 30 && shellCost <= ourCar.balance) {
                monaco.buyShell(1);
                shelled = true;
            }
            if (boostCost <= ourCar.balance) {
                monaco.buyAcceleration(2);
            }
        }

        // if we're past 75%, blow it on boost
        if (ourCar.y > MADMAX || allCars[opps1Index].y > MADMAX || allCars[opps2Index].y > MADMAX) {
            if (monaco.getAccelerateCost(MAX_ACCELERATION) <= ourCar.balance) {
                monaco.buyAcceleration(MAX_ACCELERATION / 2);
            }
        }

        uint256 rng = randomNumbaBaby(ourCar, allCars[opps1Index], allCars[opps2Index], DENIMONATOR);
        // 50% of the time, I'm gonna do something totally random. Trust bro
        if (50 < rng && !lowCash) {
            uint256 boosts = rng % MAX_ACCELERATION;
            if (0 < boosts && monaco.getAccelerateCost(boosts) <= ourCar.balance) {
                monaco.buyAcceleration(boosts);
            }

            // if we're not in the lead, coin flip for a shell. Trust me bro
            if (ourCarIndex != 0 && !shelled && shellCost <= ourCar.balance && (rng % COINFLIP) <= 1) {
                monaco.buyShell(1);
            }
        } else {
            // i guess we should make an responsible decision

            // if we're in first place, 3 acceleration
            if (ourCarIndex == 0 && (monaco.getAccelerateCost(2)) <= ourCar.balance) {
                monaco.buyAcceleration(2);
            } else {
                monaco.buyAcceleration(1);
            }
            // If we're not in the lead (index 0) + the car ahead of us is going faster + we can afford a shell, smoke em.
            if (ourCarIndex != 0 && !shelled && allCars[ourCarIndex - 1].speed > ourCar.speed && shellCost <= ourCar.balance) {
                monaco.buyShell(1); // This will instantly set the car in front of us' speed to 0.
            }

            // if we're the highest balance car, buy boost functionally
            if ((ourCar.balance - 200) > allCars[opps1Index].balance && ourCar.balance > allCars[opps2Index].balance) {
                monaco.buyAcceleration(2);
            }
        }
        // if we're stopped, buy some acceleration
        if (ourCar.speed == 0) {
            // if we're in last place, buy 2x acceleration of the second
            uint256 speedMultiplier =  (allCars[1].speed * 15) / 10;
            if (ourCarIndex == 2 && monaco.getAccelerateCost(speedMultiplier) <= ourCar.balance) {
                monaco.buyAcceleration(speedMultiplier);
            }
            // we're in second place, so maintain speed over last place
            else if (ourCarIndex == 1 && monaco.getAccelerateCost(allCars[2].speed + 1) <= ourCar.balance) {
                monaco.buyAcceleration(allCars[2].speed + 1);
            }
            // we're in first place so maintain speed over second place
            else if (ourCarIndex == 0 && monaco.getAccelerateCost(allCars[1].speed + 1) <= ourCar.balance) {
                monaco.buyAcceleration(allCars[1].speed + 1);
            }
        }

        lastBoost = boostCost;
        lastShell = shellCost;
    }
}
