// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Engine} from "../src/Engine.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();
        Engine engine = new Engine();
        deployedContracts.push(DeployData({name: "ENGINE", contractAddress: address(engine)}));
        vm.stopBroadcast();
        return deployedContracts;
    }
}
