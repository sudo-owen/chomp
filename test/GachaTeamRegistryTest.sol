// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {DefaultTeamRegistry} from "../src/teams/DefaultTeamRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {GachaRegistry} from "../src/gacha/GachaRegistry.sol";
import {Engine} from "../src/Engine.sol";
import {IGachaRNG} from "../src/rng/IGachaRNG.sol";

import {MockGachaRNG} from "./mocks/MockGachaRNG.sol";

import {IAbility} from "../src/abilities/IAbility.sol";
import {IEffect} from "../src/effects/IEffect.sol";

import {IEngine} from "../src/IEngine.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";

contract GachaTeamRegistryTest is Test {
    address constant ALICE = address(1);
    address constant BOB = address(2);

    DefaultMonRegistry monRegistry;
    GachaTeamRegistry gachaTeamRegistry;
    GachaRegistry gachaRegistry;
    Engine engine;
    MockGachaRNG mockRNG;

    uint256 constant MONS_PER_TEAM = 1;
    uint256 constant MOVES_PER_MON = 0;

    uint256 unownedMonId;

    function setUp() public {
        monRegistry = new DefaultMonRegistry();
        engine = new Engine();
        mockRNG = new MockGachaRNG();

        gachaRegistry = new GachaRegistry(monRegistry, engine, mockRNG);

        gachaTeamRegistry = new GachaTeamRegistry(
            DefaultTeamRegistry.Args({
                REGISTRY: gachaRegistry,
                MONS_PER_TEAM: MONS_PER_TEAM,
                MOVES_PER_MON: MOVES_PER_MON
            }),
            gachaRegistry
        );

        MonStats memory stats = MonStats({
            hp: 100,
            stamina: 10,
            speed: 10,
            attack: 10,
            defense: 10,
            specialAttack: 10,
            specialDefense: 10,
            type1: Type.Fire,
            type2: Type.None
        });

        IMoveSet[] memory moves = new IMoveSet[](0);

        IAbility[] memory abilities = new IAbility[](1);
        abilities[0] = IAbility(address(0));

        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);

        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS() + 1; i++) {
            monRegistry.createMon(i, stats, moves, abilities, keys, values);
        }

        // Roll for Alice (due to RNG, we should get IDs 0 to INITIAL_ROLLS)
        vm.startPrank(ALICE);
        gachaRegistry.firstRoll();

        // Set unowned mon id
        unownedMonId = gachaRegistry.INITIAL_ROLLS();
    }

    /*
     * Test that createTeam reverts when attempting to use mons not owned by the caller.
     * Verifies the ownership validation prevents unauthorized team creation.
     */
    function test_createTeam_revertsWithUnownedMon() public {
        vm.startPrank(ALICE);
        uint256[] memory monIndices = new uint256[](MONS_PER_TEAM);
        monIndices[0] = unownedMonId;
        IMoveSet[][] memory moves = new IMoveSet[][](MONS_PER_TEAM);
        IAbility[] memory abilities = new IAbility[](MONS_PER_TEAM);
        abilities[0] = IAbility(address(0));
        vm.expectRevert(GachaTeamRegistry.NotOwner.selector);
        gachaTeamRegistry.createTeam(monIndices, moves, abilities);
    }

    function test_updateTeam_revertsWithUnownedMon() public {
        vm.startPrank(ALICE);
        uint256[] memory monIndices = new uint256[](MONS_PER_TEAM);
        for (uint256 i; i < MONS_PER_TEAM; i++) {
            monIndices[i] = i;
        }
        IMoveSet[][] memory moves = new IMoveSet[][](MONS_PER_TEAM);
        IAbility[] memory abilities = new IAbility[](MONS_PER_TEAM);
        gachaTeamRegistry.createTeam(monIndices, moves, abilities);
        uint256[] memory teamMonIndicesToOverride = new uint256[](1);
        teamMonIndicesToOverride[0] = 0;
        uint256[] memory newMonIndices = new uint256[](1);
        newMonIndices[0] = unownedMonId;
        IMoveSet[][] memory newMoves = new IMoveSet[][](1);
        IAbility[] memory newAbilities = new IAbility[](1);
        vm.expectRevert(GachaTeamRegistry.NotOwner.selector);
        gachaTeamRegistry.updateTeam(0, teamMonIndicesToOverride, newMonIndices, newMoves, newAbilities);
    }

    function test_copyTeam_revertsWithUnownedMon() public {
        // Set RNG to be 1 and let bob firstRoll
        mockRNG.setRNG(1);
        vm.startPrank(BOB);
        gachaRegistry.firstRoll();

        // Bob should have ID NUM_ROLLS + 1, while Alice does not
        uint256[] memory bobMonIndices = new uint256[](MONS_PER_TEAM);
        bobMonIndices[0] = unownedMonId; // Bob will actually own this one
        IMoveSet[][] memory bobMoves = new IMoveSet[][](MONS_PER_TEAM);
        IAbility[] memory bobAbilities = new IAbility[](MONS_PER_TEAM);
        bobAbilities[0] = IAbility(address(0));
        gachaTeamRegistry.createTeam(bobMonIndices, bobMoves, bobAbilities);

        // Copy should now fail because Alice doesn't own mon ID MONS_PER_TEAM + 1
        vm.startPrank(ALICE);
        vm.expectRevert(GachaTeamRegistry.NotOwner.selector);
        gachaTeamRegistry.copyTeam(BOB, 0);
    }
}
