// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ICPURNG} from "../src/rng/ICPURNG.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {IEngine} from "../src/IEngine.sol";
import {OkayCPU} from "../src/cpu/OkayCPU.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        OkayCPU okayCPU = new OkayCPU(4, IEngine(vm.envAddress("ENGINE")), ICPURNG(address(0)), ITypeCalculator(vm.envAddress("TYPE_CALCULATOR")));
        deployedContracts.push(DeployData({name: "OKAY CPU", contractAddress: address(okayCPU)}));

        vm.stopBroadcast();
        return deployedContracts;
    }
}
