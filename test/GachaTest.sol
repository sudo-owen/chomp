/**
    - First roll only works for new accounts [x]
    - Points assigning works [x]
    - Points can be spent for rolls
    - Rolls work
    - Battle cooldown works
    - Rolls fail when all mons are owned
 */

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/Engine.sol";

import {BattleHelper} from "./abstract/BattleHelper.sol";
import {GachaRegistry} from "../src/gacha/GachaRegistry.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {MockRandomnessOracle} from "./mocks/MockRandomnessOracle.sol";

import "./mocks/TestTeamRegistry.sol";

contract GachaTest is Test, BattleHelper {

    DefaultRandomnessOracle defaultOracle;
    Engine engine;
    FastCommitManager commitManager;
    TestTeamRegistry defaultRegistry;
    DefaultMonRegistry monRegistry;
    GachaRegistry gachaRegistry;
    MockRandomnessOracle mockOracle;

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setCommitManager(address(commitManager));
        defaultRegistry = new TestTeamRegistry();
        monRegistry = new DefaultMonRegistry();
        mockOracle = new MockRandomnessOracle();
        gachaRegistry = new GachaRegistry(monRegistry, engine, mockOracle);
    }

    function test_firstRoll() public {

        // Set up mon IDs 0 to INITIAL ROLLS
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(i, MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }), new IMoveSet[](0), new IAbility[](0), new bytes32[](0), new bytes32[](0));
        }

        vm.prank(ALICE);
        uint256[] memory monIds = gachaRegistry.firstRoll();
        assertEq(monIds.length, gachaRegistry.INITIAL_ROLLS());

        // Alice rolls again, it should fail
        vm.expectRevert(GachaRegistry.AlreadyFirstRolled.selector);
        vm.prank(ALICE);
        gachaRegistry.firstRoll();
    }

    function test_assignPoints() public {
        // Set up mon IDs 0 to INITIAL ROLLS
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(i, MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }), new IMoveSet[](0), new IAbility[](0), new bytes32[](0), new bytes32[](0));
        }

        // Start battle
        vm.warp(gachaRegistry.BATTLE_COOLDOWN() + 1);
        FastValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 0, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0})
        );
        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, gachaRegistry);

        // Alice commits switching to mon index 0
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, "", abi.encode(0))));

        // Alice wins the battle (inactivity for Bob), we skip ahead
        mockOracle.setRNG(1); // No extra bonus for points
        vm.warp(block.timestamp + 1);
        engine.end(battleKey);

        // Assert Alice won
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);

        // Verify points are correct
        assertEq(gachaRegistry.pointsBalance(ALICE), gachaRegistry.POINTS_PER_WIN());
        assertEq(gachaRegistry.pointsBalance(BOB), gachaRegistry.POINTS_PER_LOSS());
    }

    function test_spendPoints() public {
        // Set up mon IDs 0 to INITIAL ROLLS
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(i, MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }), new IMoveSet[](0), new IAbility[](0), new bytes32[](0), new bytes32[](0));
        }

        mockOracle.setRNG(1); // No extra bonus for points

        // Start battle (do it 6 times so Alice has enough to spend on a roll)
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(gachaRegistry.BATTLE_COOLDOWN() * (i + 1) + (i+1));
            FastValidator validator = new FastValidator(
                engine, FastValidator.Args({MONS_PER_TEAM: 0, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0})
            );
            defaultRegistry.setTeam(ALICE, new Mon[](0));
            bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, gachaRegistry);

            // Alice commits switching to mon index 0
            vm.startPrank(ALICE);
            commitManager.commitMove(battleKey, keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, "", abi.encode(0))));

            // Alice wins the battle
            engine.end(battleKey);
        }

        // Assert Alice has enough points to roll
        assertEq(gachaRegistry.pointsBalance(ALICE), 6 * gachaRegistry.POINTS_PER_WIN());
    }
}
