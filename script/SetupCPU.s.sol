// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract SetupCPU is Script {

    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {

        vm.startBroadcast();

        // Create team of Ghouliath, Malalien, Pengym, and Volthare for RandomCPU player
        uint256[] memory monIndices = new uint256[](4);
        monIndices[0] = 0; // Ghouliath
        monIndices[1] = 2; // Malalien
        monIndices[2] = 6; // Pengym
        monIndices[3] = 8; // Volthare

        GachaTeamRegistry gachaTeamRegistry = GachaTeamRegistry(vm.envAddress("GACHA_TEAM_REGISTRY"));
        gachaTeamRegistry.createTeamForUser(vm.envAddress("RANDOM_CPU"), monIndices);
        gachaTeamRegistry.createTeamForUser(vm.envAddress("PLAYER_CPU"), monIndices);

        vm.stopBroadcast();

        return deployedContracts;
    }
}
