// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IEngine} from "../src/IEngine.sol";
import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();
        DefaultMatchmaker matchmaker = new DefaultMatchmaker(IEngine(vm.envAddress("ENGINE")));
        deployedContracts.push(DeployData({name: "DEFAULT MATCHMAKER", contractAddress: address(matchmaker)}));
        vm.stopBroadcast();

        return deployedContracts;
    }
}
