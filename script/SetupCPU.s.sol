// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {IAbility} from "../src/abilities/IAbility.sol";
import {IEffect} from "../src/effects/IEffect.sol";
import {Engine} from "../src/Engine.sol";
import {IEngine} from "../src/IEngine.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";
import {DefaultRuleset} from "../src/DefaultRuleset.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";
import {TypeCalculator} from "../src/types/TypeCalculator.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaRegistry, IGachaRNG} from "../src/gacha/GachaRegistry.sol";
import {GachaTeamRegistry, DefaultTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ICPURNG} from "../src/rng/ICPURNG.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";
import {RandomCPU} from "../src/cpu/RandomCPU.sol";
import {FirstCPU} from "../src/cpu/FirstCPU.sol";
import {MonStats} from "../src/Structs.sol";
import {Type} from "../src/Enums.sol";

// Important effects
import {StatBoosts} from "../src/effects/StatBoosts.sol";
import {Storm} from "../src/effects/weather/Storm.sol";
import {SleepStatus} from "../src/effects/status/SleepStatus.sol";
import {PanicStatus} from "../src/effects/status/PanicStatus.sol";
import {FrostbiteStatus} from "../src/effects/status/FrostbiteStatus.sol";
import {BurnStatus} from "../src/effects/status/BurnStatus.sol";
import {ZapStatus} from "../src/effects/status/ZapStatus.sol";

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

        GachaTeamRegistry gachaTeamRegistry = GachaTeamRegistry(vm.envAddress("GACHA_TEAM_REGISTRY"));
        
        FirstCPU firstCPU = new FirstCPU(4, IEngine(vm.envAddress("ENGINE")), ICPURNG(vm.envAddress("DEFAULT_RANDOMNESS_ORACLE")));
        deployedContracts.push(DeployData({
            name: "FIRST CPU",
            contractAddress: address(firstCPU)
        }));
        CPUMoveManager cpuMoveManager = new CPUMoveManager(IEngine(vm.envAddress("ENGINE")), firstCPU);
        deployedContracts.push(DeployData({
            name: "CPU MOVE MANAGER",
            contractAddress: address(cpuMoveManager)
        }));

        gachaTeamRegistry.createTeamForUser(address(cpuMoveManager), monIndices, moves, abilities);

        vm.stopBroadcast();

        return deployedContracts;
    }
}
