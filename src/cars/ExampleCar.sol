// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Car.sol";

contract ExampleCar is Car {
    constructor(Monaco _monaco) Car(_monaco) {}

    function takeYourTurn(Monaco.CarData[] calldata allCars, uint256 ourCarIndex) external override {
        Monaco.CarData memory ourCar = allCars[ourCarIndex];

        // If we can afford to accelerate 3 times, let's do it.
        if (ourCar.balance > monaco.getAccelerateCost(3)) ourCar.balance -= uint24(monaco.buyAcceleration(3));

        // If we're not in the lead (index 0) + the car ahead of us is going faster + we can afford a shell, smoke em.
        if (ourCarIndex != 0 && allCars[ourCarIndex - 1].speed > ourCar.speed && ourCar.balance > monaco.getShellCost(1)) {
            monaco.buyShell(1); // This will instantly set the car in front of us' speed to 0.
        }
    }
}
