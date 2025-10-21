// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/Engine.sol";

import {DefaultCommitManager} from "../src/DefaultCommitManager.sol";

import {FastValidator} from "../src/FastValidator.sol";
import {GachaRegistry} from "../src/gacha/GachaRegistry.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";

import {IGachaRNG} from "../src/rng/IGachaRNG.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {BattleHelper} from "./abstract/BattleHelper.sol";

import {MockGachaRNG} from "./mocks/MockGachaRNG.sol";
import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";

import "./mocks/TestTeamRegistry.sol";

contract GachaTest is Test, BattleHelper {
    DefaultRandomnessOracle defaultOracle;
    Engine engine;
    DefaultCommitManager commitManager;
    TestTeamRegistry defaultRegistry;
    DefaultMonRegistry monRegistry;
    MockGachaRNG mockRNG;
    DefaultMatchmaker matchmaker;

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new DefaultCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        defaultRegistry = new TestTeamRegistry();
        monRegistry = new DefaultMonRegistry();
        mockRNG = new MockGachaRNG();
        matchmaker = new DefaultMatchmaker(engine);
    }

    function test_firstRoll() public {
        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, mockRNG);

        // Set up mon IDs 0 to INITIAL ROLLS
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(
                i,
                MonStats({
                    hp: 10,
                    stamina: 2,
                    speed: 2,
                    attack: 1,
                    defense: 1,
                    specialAttack: 1,
                    specialDefense: 1,
                    type1: Type.Fire,
                    type2: Type.None
                }),
                new IMoveSet[](0),
                new IAbility[](0),
                new bytes32[](0),
                new bytes32[](0)
            );
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
        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, mockRNG);

        // Set up mon IDs 0 to INITIAL ROLLS
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(
                i,
                MonStats({
                    hp: 10,
                    stamina: 2,
                    speed: 2,
                    attack: 1,
                    defense: 1,
                    specialAttack: 1,
                    specialDefense: 1,
                    type1: Type.Fire,
                    type2: Type.None
                }),
                new IMoveSet[](0),
                new IAbility[](0),
                new bytes32[](0),
                new bytes32[](0)
            );
        }

        // Start battle
        Mon[] memory team = new Mon[](1);
        team[0] = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: new IMoveSet[](0),
            ability: IAbility(address(0))
        });
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        vm.warp(gachaRegistry.BATTLE_COOLDOWN() + 1);
        FastValidator validator =
            new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0}));
        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, gachaRegistry);

        // Alice commits switching to mon index 0
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, "", abi.encode(0))));

        // Alice wins the battle (inactivity for Bob), we skip ahead
        mockRNG.setRNG(1); // No extra bonus for points
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
        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, mockRNG);

        // Set up mon IDs 0 to INITIAL ROLLS + 1
        for (uint256 i = 0; i < gachaRegistry.INITIAL_ROLLS(); i++) {
            monRegistry.createMon(
                i,
                MonStats({
                    hp: 10,
                    stamina: 2,
                    speed: 2,
                    attack: 1,
                    defense: 1,
                    specialAttack: 1,
                    specialDefense: 1,
                    type1: Type.Fire,
                    type2: Type.None
                }),
                new IMoveSet[](0),
                new IAbility[](0),
                new bytes32[](0),
                new bytes32[](0)
            );
        }

        // Start battle (do it 6 times so Alice has enough to spend on a roll)
        Mon[] memory team = new Mon[](1);
        team[0] = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: new IMoveSet[](0),
            ability: IAbility(address(0))
        });
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(gachaRegistry.BATTLE_COOLDOWN() * (i + 1) + (i + 1));
            FastValidator validator =
                new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0}));
            bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, gachaRegistry);

            // Alice commits switching to mon index 0
            vm.startPrank(ALICE);
            commitManager.commitMove(battleKey, keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, "", abi.encode(0))));

            // Alice wins the battle
            engine.end(battleKey);
        }

        // Assert Alice has enough points to roll
        assertEq(gachaRegistry.pointsBalance(ALICE), 6 * gachaRegistry.POINTS_PER_WIN());

        // Alice rolls
        vm.startPrank(ALICE);
        // (Do first roll first)
        gachaRegistry.firstRoll();
        vm.expectRevert(GachaRegistry.NoMoreStock.selector);
        uint256[] memory monIds = gachaRegistry.roll(1);
        vm.stopPrank();

        // Add one more mon to the registry and roll again
        monRegistry.createMon(
            gachaRegistry.INITIAL_ROLLS(),
            MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            new IMoveSet[](0),
            new IAbility[](0),
            new bytes32[](0),
            new bytes32[](0)
        );
        vm.startPrank(ALICE);
        monIds = gachaRegistry.roll(1);
        assertEq(monIds.length, 1);

        // Verify points are correct
        assertEq(gachaRegistry.pointsBalance(ALICE), 0);

        // Verify Alice cannot roll again (should underflow)
        vm.expectRevert();
        gachaRegistry.roll(1);

        // Verify Alice balance is 0
        assertEq(gachaRegistry.pointsBalance(ALICE), 0);
    }

    function test_bonusPoints() public {
        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, IGachaRNG(address(0)));
        FastValidator validator =
            new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0}));
        Mon[] memory team = new Mon[](1);
        team[0] = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: new IMoveSet[](0),
            ability: IAbility(address(0))
        });
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        vm.warp(gachaRegistry.BATTLE_COOLDOWN() + 1);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, gachaRegistry);
        
        // Magic number to trigger the bonus points after all the hashing we do
        bytes32 salt = keccak256(abi.encode(11));

        bytes32 aliceMoveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, abi.encode(0)));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, aliceMoveHash);
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);

        // Alice wins the battle because timeout duration is 0, so we auto force a lose
        // It's turn id 1 which means Bob had to commit, so any inaction is a lose from him
        engine.end(battleKey);
        assertEq(engine.getWinner(battleKey), ALICE);

        // Verify points are correct
        assertEq(
            gachaRegistry.pointsBalance(ALICE), gachaRegistry.POINTS_MULTIPLIER() * gachaRegistry.POINTS_PER_WIN()
        );
        assertEq(gachaRegistry.pointsBalance(BOB), gachaRegistry.POINTS_MULTIPLIER() * gachaRegistry.POINTS_PER_LOSS());
    }

    function test_cooldown() public {
        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, IGachaRNG(address(0)));
        FastValidator validator =
            new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0}));
        Mon[] memory team = new Mon[](1);
        team[0] = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: new IMoveSet[](0),
            ability: IAbility(address(0))
        });
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        vm.warp(gachaRegistry.BATTLE_COOLDOWN() + 1);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, gachaRegistry);
        
        // Magic number to trigger the bonus points after all the hashing we do
        bytes32 salt = keccak256(abi.encode(11));

        bytes32 aliceMoveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, abi.encode(0)));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, aliceMoveHash);
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);

        // Alice wins the battle
        engine.end(battleKey);
        assertEq(engine.getWinner(battleKey), ALICE);

        // Assert Alice and Bob have nonzero points 
        uint256 alicePoints = gachaRegistry.pointsBalance(ALICE);
        uint256 bobPoints = gachaRegistry.pointsBalance(BOB);
        assertGt(alicePoints, 0);
        assertGt(bobPoints, 0);

        // Start another battle
        battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, gachaRegistry);
        aliceMoveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, abi.encode(0)));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, aliceMoveHash);
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(0), true);

        // Alice wins the battle
        engine.end(battleKey);
        assertEq(engine.getWinner(battleKey), ALICE);

        // Assert Alice and Bob have the same points as before
        assertEq(gachaRegistry.pointsBalance(ALICE), alicePoints);
        assertEq(gachaRegistry.pointsBalance(BOB), bobPoints);
    }
}
