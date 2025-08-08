// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Type} from "../src/Enums.sol";

import {IEngine} from "../src/IEngine.sol";
import {MonStats} from "../src/Structs.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

import {IEffect} from "../src/effects/IEffect.sol";
import {DualShock} from "../src/mons/volthare/DualShock.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {ICPURNG} from "../src/rng/ICPURNG.sol";
import {RandomCPU} from "../src/cpu/RandomCPU.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";

import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();
        // Redeploy RandomCPU
        RandomCPU cpu = new RandomCPU(4, IEngine(vm.envAddress("ENGINE")), ICPURNG(address(0)));
        deployedContracts.push(DeployData({
            name: "RANDOM CPU",
            contractAddress: address(cpu)
        }));
        CPUMoveManager cpuMoveManager = new CPUMoveManager(IEngine(vm.envAddress("ENGINE")), cpu);
        deployedContracts.push(DeployData({
            name: "CPU MOVE MANAGER",
            contractAddress: address(cpuMoveManager)
        }));
        vm.stopBroadcast();

        return deployedContracts;
    }
}
