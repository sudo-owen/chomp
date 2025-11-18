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
        string[] memory cpuPlayers = new string[](3);
        cpuPlayers[0] = "RANDOM_CPU";
        cpuPlayers[1] = "PLAYER_CPU";
        cpuPlayers[2] = "OKAY_CPU";
        for (uint256 i; i < cpuPlayers.length; i++) {
            gachaTeamRegistry.createTeamForUser(vm.envAddress(cpuPlayers[i]), monIndices);
        }

        // Create alternative team
        monIndices[0] = 1; // Inutia
        monIndices[1] = 3; // Iblivion
        monIndices[2] = 4; // Gorillax
        monIndices[3] = 5; // Sofabbi

        for (uint256 i; i < cpuPlayers.length; i++) {
            gachaTeamRegistry.createTeamForUser(vm.envAddress(cpuPlayers[i]), monIndices);
        }

        // Create team of Embursa, Aurox, Xmon, and Ghouliath
        monIndices[0] = 7; // Embursa
        monIndices[1] = 9; // Aurox
        monIndices[2] = 10; // Ghouliath
        monIndices[3] = 0; // Gorillax

        for (uint256 i; i < cpuPlayers.length; i++) {
            gachaTeamRegistry.createTeamForUser(vm.envAddress(cpuPlayers[i]), monIndices);
        }

        vm.stopBroadcast();

        return deployedContracts;
    }
}
