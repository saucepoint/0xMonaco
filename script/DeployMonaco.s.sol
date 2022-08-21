// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/Monaco.sol";

contract DeployMonaco is Script {
    function run() public {
        vm.startBroadcast();

        new Monaco();
    }
}
