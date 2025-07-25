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

contract Surgery is Script {

    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {

        vm.startBroadcast();

        // Redeploy registries
        DefaultMonRegistry monRegistry = new DefaultMonRegistry();
        deployedContracts.push(DeployData({
            name: "DEFAULT MON REGISTRY",
            contractAddress: address(monRegistry)
        }));

        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, IEngine(vm.envAddress("ENGINE")), IGachaRNG(address(0)));
        deployedContracts.push(DeployData({
            name: "GACHA REGISTRY",
            contractAddress: address(gachaRegistry)
        }));

        GachaTeamRegistry gachaTeamRegistry = new GachaTeamRegistry(
            DefaultTeamRegistry.Args({
                REGISTRY: gachaRegistry,
                MONS_PER_TEAM: 4,
                MOVES_PER_MON: 4
            }),
            gachaRegistry
        );
        deployedContracts.push(DeployData({
            name: "GACHA TEAM REGISTRY",
            contractAddress: address(gachaTeamRegistry)
        }));

        // Create all mons using pre-deployed contract addresses
        createGhouliath(monRegistry);
        createInutia(monRegistry);
        createMalalien(monRegistry);
        createIblivion(monRegistry);
        createGorillax(monRegistry);
        createSofabbi(monRegistry);
        createPengym(monRegistry);
        createEmbursa(monRegistry);
        createVolthare(monRegistry);

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

        gachaTeamRegistry.createTeamForUser(vm.envAddress("RANDOM_CPU"), monIndices, moves, abilities);

        vm.stopBroadcast();

        return deployedContracts;
    }

    function createGhouliath(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 303,
            stamina: 5,
            speed: 181,
            attack: 157,
            defense: 202,
            specialAttack: 151,
            specialDefense: 202,
            type1: Type.Yang,
            type2: Type.Fire
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("ETERNAL_GRUDGE"));
        moves[1] = IMoveSet(vm.envAddress("INFERNAL_FLAME"));
        moves[2] = IMoveSet(vm.envAddress("WITHER_AWAY"));
        moves[3] = IMoveSet(vm.envAddress("OSTEOPOROSIS"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("RISE_FROM_THE_GRAVE"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(0, stats, moves, abilities, keys, values);
    }

    function createInutia(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 351,
            stamina: 5,
            speed: 259,
            attack: 171,
            defense: 189,
            specialAttack: 175,
            specialDefense: 192,
            type1: Type.Wild,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("CHAIN_EXPANSION"));
        moves[1] = IMoveSet(vm.envAddress("INITIALIZE"));
        moves[2] = IMoveSet(vm.envAddress("BIG_BITE"));
        moves[3] = IMoveSet(vm.envAddress("SHRINE_STRIKE"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("INTERWEAVING"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(1, stats, moves, abilities, keys, values);
    }

    function createMalalien(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 258,
            stamina: 5,
            speed: 308,
            attack: 121,
            defense: 125,
            specialAttack: 322,
            specialDefense: 151,
            type1: Type.Cyber,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("TRIPLE_THINK"));
        moves[1] = IMoveSet(vm.envAddress("FEDERAL_INVESTIGATION"));
        moves[2] = IMoveSet(vm.envAddress("NEGATIVE_THOUGHTS"));
        moves[3] = IMoveSet(vm.envAddress("INFINITE_LOVE"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("ACTUS_REUS"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(2, stats, moves, abilities, keys, values);
    }

    function createIblivion(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 277,
            stamina: 5,
            speed: 256,
            attack: 188,
            defense: 164,
            specialAttack: 240,
            specialDefense: 168,
            type1: Type.Cosmic,
            type2: Type.Air
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("BASELIGHT"));
        moves[1] = IMoveSet(vm.envAddress("LOOP"));
        moves[2] = IMoveSet(vm.envAddress("FIRST_RESORT"));
        moves[3] = IMoveSet(vm.envAddress("BRIGHTBACK"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("INTRINSIC_VALUE"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(3, stats, moves, abilities, keys, values);
    }

    function createGorillax(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 407,
            stamina: 5,
            speed: 129,
            attack: 302,
            defense: 175,
            specialAttack: 112,
            specialDefense: 176,
            type1: Type.Earth,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("ROCK_PULL"));
        moves[1] = IMoveSet(vm.envAddress("POUND_GROUND"));
        moves[2] = IMoveSet(vm.envAddress("BLOW"));
        moves[3] = IMoveSet(vm.envAddress("THROW_PEBBLE"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("ANGERY"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(4, stats, moves, abilities, keys, values);
    }

    function createSofabbi(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 333,
            stamina: 5,
            speed: 205,
            attack: 180,
            defense: 201,
            specialAttack: 120,
            specialDefense: 269,
            type1: Type.Nature,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("GACHACHACHA"));
        moves[1] = IMoveSet(vm.envAddress("GUEST_FEATURE"));
        moves[2] = IMoveSet(vm.envAddress("UNEXPECTED_CARROT"));
        moves[3] = IMoveSet(vm.envAddress("SNACK_BREAK"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("CARROT_HARVEST"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(5, stats, moves, abilities, keys, values);
    }

    function createPengym(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 371,
            stamina: 5,
            speed: 149,
            attack: 212,
            defense: 191,
            specialAttack: 233,
            specialDefense: 172,
            type1: Type.Ice,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("CHILL_OUT"));
        moves[1] = IMoveSet(vm.envAddress("DEADLIFT"));
        moves[2] = IMoveSet(vm.envAddress("DEEP_FREEZE"));
        moves[3] = IMoveSet(vm.envAddress("PISTOL_SQUAT"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("POST_WORKOUT"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(6, stats, moves, abilities, keys, values);
    }

    function createEmbursa(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 420,
            stamina: 5,
            speed: 111,
            attack: 141,
            defense: 230,
            specialAttack: 180,
            specialDefense: 161,
            type1: Type.Fire,
            type2: Type.None
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("HONEY_BRIBE"));
        moves[1] = IMoveSet(vm.envAddress("SET_ABLAZE"));
        moves[2] = IMoveSet(vm.envAddress("HEAT_BEACON"));
        moves[3] = IMoveSet(vm.envAddress("Q5"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("SPLIT_THE_POT"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(7, stats, moves, abilities, keys, values);
    }

    function createVolthare(DefaultMonRegistry registry) internal {
        MonStats memory stats = MonStats({
            hp: 303,
            stamina: 5,
            speed: 311,
            attack: 120,
            defense: 184,
            specialAttack: 255,
            specialDefense: 176,
            type1: Type.Lightning,
            type2: Type.Cyber
        });
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = IMoveSet(vm.envAddress("ELECTROCUTE"));
        moves[1] = IMoveSet(vm.envAddress("ROUND_TRIP"));
        moves[2] = IMoveSet(vm.envAddress("MEGA_STAR_BLAST"));
        moves[3] = IMoveSet(vm.envAddress("DUAL_SHOCK"));
        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(vm.envAddress("OVERCLOCK"));
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);
        registry.createMon(8, stats, moves, abilities, keys, values);
    }
}
