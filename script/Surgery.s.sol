// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

contract Surgery is Script {

    function run() external {

        vm.startBroadcast();

        // Create a new team for the RandomCPU player
        GachaTeamRegistry teamRegistry = GachaTeamRegistry(vm.envAddress("GACHA_TEAM_REGISTRY"));
        uint256[] memory monIndices = new uint256[](4);
        monIndices[0] = 0; // Ghouliath
        monIndices[1] = 2; // Malalien
        monIndices[2] = 6; // Pengym
        monIndices[3] = 8; // Volthare

        IMoveSet[][] memory moves = new IMoveSet[][](4);
        IAbility[] memory abilities = new IAbility[](4);

        // Ghouliath moves and ability (mon index 0)
        moves[0] = new IMoveSet[](4);
        moves[0][0] = IMoveSet(vm.envAddress("ETERNAL_GRUDGE"));
        moves[0][1] = IMoveSet(vm.envAddress("INFERNAL_FLAME"));
        moves[0][2] = IMoveSet(vm.envAddress("WITHER_AWAY"));
        moves[0][3] = IMoveSet(vm.envAddress("OSTEOPOROSIS"));
        abilities[0] = IAbility(vm.envAddress("RISE_FROM_THE_GRAVE"));

        // Malalien moves and ability (mon index 2)
        moves[1] = new IMoveSet[](4);
        moves[1][0] = IMoveSet(vm.envAddress("TRIPLE_THINK"));
        moves[1][1] = IMoveSet(vm.envAddress("FEDERAL_INVESTIGATION"));
        moves[1][2] = IMoveSet(vm.envAddress("NEGATIVE_THOUGHTS"));
        moves[1][3] = IMoveSet(vm.envAddress("INFINITE_LOVE"));
        abilities[1] = IAbility(vm.envAddress("ACTUS_REUS"));

        // Pengym moves and ability (mon index 6)
        moves[2] = new IMoveSet[](4);
        moves[2][0] = IMoveSet(vm.envAddress("CHILL_OUT"));
        moves[2][1] = IMoveSet(vm.envAddress("DEADLIFT"));
        moves[2][2] = IMoveSet(vm.envAddress("DEEP_FREEZE"));
        moves[2][3] = IMoveSet(vm.envAddress("PISTOL_SQUAT"));
        abilities[2] = IAbility(vm.envAddress("POST_WORKOUT"));

        // Volthare moves and ability (mon index 8)
        moves[3] = new IMoveSet[](4);
        moves[3][0] = IMoveSet(vm.envAddress("ELECTROCUTE"));
        moves[3][1] = IMoveSet(vm.envAddress("ROUND_TRIP"));
        moves[3][2] = IMoveSet(vm.envAddress("MEGA_STAR_BLAST"));
        moves[3][3] = IMoveSet(vm.envAddress("DUAL_SHOCK"));
        abilities[3] = IAbility(vm.envAddress("OVERCLOCK"));

        teamRegistry.createTeamForUser(vm.envAddress("RANDOM_CPU"), monIndices, moves, abilities);
        vm.stopBroadcast();
    }
}
