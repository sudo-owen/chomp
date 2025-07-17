// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {Engine} from "../src/Engine.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {IValidator} from "../src/IValidator.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

import {IEffect} from "../src/effects/IEffect.sol";

import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {CustomAttack} from "./mocks/CustomAttack.sol";

import {AfterDamageReboundEffect} from "./mocks/AfterDamageReboundEffect.sol";
import {EffectAbility} from "./mocks/EffectAbility.sol";
import {EffectAttack} from "./mocks/EffectAttack.sol";
import {ForceSwitchMove} from "./mocks/ForceSwitchMove.sol";
import {GlobalEffectAttack} from "./mocks/GlobalEffectAttack.sol";
import {InstantDeathOnSwitchInEffect} from "./mocks/InstantDeathOnSwitchInEffect.sol";
import {InvalidMove} from "./mocks/InvalidMove.sol";
import {MockRandomnessOracle} from "./mocks/MockRandomnessOracle.sol";

import {OneTurnStatBoost} from "./mocks/OneTurnStatBoost.sol";
import {SingleInstanceEffect} from "./mocks/SingleInstanceEffect.sol";
import {SkipTurnMove} from "./mocks/SkipTurnMove.sol";
import {TempStatBoostEffect} from "./mocks/TempStatBoostEffect.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";
import {BattleHelper} from "./abstract/BattleHelper.sol";
import {IEngineHook} from "../src/IEngineHook.sol";
import {IMoveManager} from "../src/IMoveManager.sol";

import {TestTypeCalculator} from "./mocks/TestTypeCalculator.sol";

contract FastEngineTest is Test, BattleHelper {
    FastCommitManager commitManager;
    Engine engine;
    ITypeCalculator typeCalc;
    DefaultRandomnessOracle defaultOracle;
    TestTeamRegistry defaultRegistry;

    address constant CARL = address(3);
    uint256 constant TIMEOUT_DURATION = 100;

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        typeCalc = new TestTypeCalculator();
        defaultRegistry = new TestTeamRegistry();
    }

    // Helper function, creates a battle with two mons each for Alice and Bob
    function _startDummyBattle() internal returns (bytes32) {
        IMoveSet[] memory moves = new IMoveSet[](1);
        Mon memory dummyMon = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 1,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory dummyTeam = new Mon[](2);
        dummyTeam[0] = dummyMon;
        dummyTeam[1] = dummyMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, dummyTeam);
        defaultRegistry.setTeam(BOB, dummyTeam);

        // Set up validator
        FastValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Setup battle
        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry);

        return battleKey;
    }

    function _commitRevealExecuteForAliceAndBob(
        bytes32 battleKey,
        uint256 aliceMoveIndex,
        uint256 bobMoveIndex,
        bytes memory aliceExtraData,
        bytes memory bobExtraData
    ) internal {
        bytes32 salt = "";
        bytes32 aliceMoveHash = keccak256(abi.encodePacked(aliceMoveIndex, salt, aliceExtraData));
        bytes32 bobMoveHash = keccak256(abi.encodePacked(bobMoveIndex, salt, bobExtraData));
        // Decide which player commits
        uint256 turnId = engine.getTurnIdForBattleState(battleKey);
        if (turnId % 2 == 0) {
            vm.startPrank(ALICE);
            commitManager.commitMove(battleKey, aliceMoveHash);
            vm.startPrank(BOB);
            commitManager.revealMove(battleKey, bobMoveIndex, salt, bobExtraData, true);
            vm.startPrank(ALICE);
            commitManager.revealMove(battleKey, aliceMoveIndex, salt, aliceExtraData, true);
        } else {
            vm.startPrank(BOB);
            commitManager.commitMove(battleKey, bobMoveHash);
            vm.startPrank(ALICE);
            commitManager.revealMove(battleKey, aliceMoveIndex, salt, aliceExtraData, true);
            vm.startPrank(BOB);
            commitManager.revealMove(battleKey, bobMoveIndex, salt, bobExtraData, true);
        }
    }

    function test_commitBattleWithoutAcceptReverts() public {
        /*
        - both players can propose (without accepting) and nonce will not increase (i.e. battle key does not change)
        - accepting a battle increments the nonce for the next propose (i.e. battle key changes)
        - committing should fail if the battle is not accepted
        */

        IMoveSet[] memory moves = new IMoveSet[](1);
        Mon memory dummyMon = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 1,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[] memory dummyTeam = new Mon[](1);
        dummyTeam[0] = dummyMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, dummyTeam);
        defaultRegistry.setTeam(BOB, dummyTeam);

        // Set up validator
        FastValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        Battle memory args = Battle({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            engineHook: IEngineHook(address(0)),
            moveManager: IMoveManager(address(0)),
            teams: new Mon[][](0),
            status: BattleProposalStatus.Proposed,
            p1TeamIndex: 0
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);

        // Have Bob propose a battle
        vm.startPrank(BOB);
        Battle memory bobArgs = Battle({
            p0: BOB,
            p1: ALICE,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(BOB, 0))
            ),
            engineHook: IEngineHook(address(0)),
            moveManager: IMoveManager(address(0)),
            teams: new Mon[][](0),
            status: BattleProposalStatus.Proposed,
            p1TeamIndex: 0
        });
        bytes32 updatedBattleKey = engine.proposeBattle(bobArgs);

        // Battle key should be the same when no one accepts
        assertEq(battleKey, updatedBattleKey);

        // Assert it reverts for Alice upon commit
        vm.expectRevert(FastCommitManager.BattleNotStarted.selector);
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, "");

        // Assert it reverts for Bob upon commit
        vm.expectRevert(FastCommitManager.BattleNotStarted.selector);
        vm.startPrank(BOB);
        commitManager.commitMove(battleKey, "");

        // Have Alice accept the battle Bob proposed
        vm.startPrank(ALICE);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, bobArgs.p0TeamHash, args.engineHook, args.moveManager)
        );
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);

        // Have Bob start the Battle (given that Alice accepted)
        vm.startPrank(BOB);
        engine.startBattle(battleKey, "", 0);

        // Have Bob propose a new battle
        vm.warp(validator.TIMEOUT_DURATION() + 1);
        vm.startPrank(BOB);
        bytes32 newBattleKey = engine.proposeBattle(bobArgs);

        // Battle key should be different when one accepts
        assertNotEq(battleKey, newBattleKey);
    }

    function test_anyoneCanFillP1() public {
        // Create validator with zero mons and zero moves needed
        FastValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        Mon[] memory dummyTeam = new Mon[](1);
        IMoveSet[] memory moves = new IMoveSet[](0);
        dummyTeam[0] = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 1,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        // Register teams
        defaultRegistry.setTeam(ALICE, dummyTeam);
        defaultRegistry.setTeam(BOB, dummyTeam);

        // Create a battle with Alice as p0 and zero address as p1
        bytes32 aliceTeamHash = keccak256(
            abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
        );
        Battle memory args = Battle({
            p0: ALICE,
            p1: address(0),
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: aliceTeamHash,
            engineHook: IEngineHook(address(0)),
            moveManager: IMoveManager(address(0)),
            teams: new Mon[][](0),
            status: BattleProposalStatus.Proposed,
            p1TeamIndex: 0
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        vm.startPrank(BOB);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, aliceTeamHash, args.engineHook, args.moveManager)
        );
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.startPrank(ALICE);
        engine.startBattle(battleKey, "", 0);

        // Verify Bob is now p1
        assertEq(engine.getPlayersForBattle(battleKey)[1], BOB);
    }

    /*
    Checks that:
    - reveal for player who has to commit) correctly reverts if they haven't committed
    - reveal for player who does not have to commit() correctly reverts if the other player hasn't committed
    - non-players cannot commit or reveal
    - revealing an invalid move reverts
    - after revealing a valid move, auto-execute advances game state
    */
    function test_turn0FastCommitManagerValidPreimage() public {
        bytes32 battleKey = _startDummyBattle();
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));

        // Ensure Alice cannot reveal yet because Alice has not yet committed
        // It is turn 0, so Alice must first commit then reveal
        // We will attempt to calculate the preimage, which will fail
        vm.startPrank(ALICE);
        vm.expectRevert(FastCommitManager.WrongPreimage.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Bob cannot commit as they only need to reveal
        vm.startPrank(BOB);
        vm.expectRevert(FastCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Bob cannot reveal yet as Alice has not committed
        vm.expectRevert(FastCommitManager.RevealBeforeOtherCommit.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Carl cannot commit as they are not in the battle
        vm.startPrank(CARL);
        vm.expectRevert(FastCommitManager.NotP0OrP1.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Carl should also be unable to reveal
        vm.expectRevert(FastCommitManager.NotP0OrP1.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Let Alice commit the first move (switching in mon index 0)
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, moveHash);

        // Let Bob reveal their invalid move index of 0
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", BOB));
        commitManager.revealMove(battleKey, 0, salt, extraData, true);

        // Now let Bob reveal a valid move
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Alice reveals her move
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Assert that the game state executed
        uint256 turnId = engine.getTurnIdForBattleState(battleKey);
        assertEq(turnId, 1);
    }

    /*
    Checks that:
    - committing an invalid state prevents reveal
    - advancing state has the same reverts as expected, but now for the other player index
    */
    function test_turn0FastCommitManagerInvalidPreimage() public {
        bytes32 battleKey = _startDummyBattle();

        // Let Alice commit to choosing switch
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));

        // Let Alice commit the first move (switching in mon index 0)
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, moveHash);

        // Let Bob reveal their invalid move index of 0
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Alice reveals her move incorrectly, leading to an error
        vm.startPrank(ALICE);
        vm.expectRevert(FastCommitManager.WrongPreimage.selector);
        commitManager.revealMove(battleKey, 0, salt, extraData, true);

        // Alice correctly reveals her move, advancing the game state
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // New turn, both players swap to mon index 1
        extraData = abi.encode(1);
        moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));

        // Ensure Bob cannot reveal yet because Bob has not yet committed
        // It is turn 1, so Bob must first commit then reveal
        // We will attempt to calculate the preimage, which will fail
        vm.startPrank(BOB);
        vm.expectRevert(FastCommitManager.WrongPreimage.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Alice cannot commit as they only need to reveal
        vm.startPrank(ALICE);
        vm.expectRevert(FastCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Alice cannot reveal yet as Bob has not committed
        vm.expectRevert(FastCommitManager.RevealBeforeOtherCommit.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Let Bob commit the first move (switching in mon index 0)
        vm.startPrank(BOB);
        commitManager.commitMove(battleKey, moveHash);

        // Let Alice reveal their invalid move index of 0
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", ALICE));
        bytes memory invalidExtraData = abi.encode(0);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, invalidExtraData, true);

        // Now let Alice reveal a valid move
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Bob reveals their move
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Assert that the game state executed
        uint256 turnId = engine.getTurnIdForBattleState(battleKey);
        assertEq(turnId, 2);
    }

    function test_canStartBattleBothPlayersNoOpAfterSwap() public {
        bytes32 battleKey = _startDummyBattle();

        // Let Alice commit to choosing switch
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, moveHash);

        // Let Bob reveal to choosing switch as well
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Let Alice reveal and advance game state
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Set args for a no op
        extraData = "";
        moveHash = keccak256(abi.encodePacked(NO_OP_MOVE_INDEX, salt, extraData));

        // Let Bob commit
        vm.startPrank(BOB);
        commitManager.commitMove(battleKey, moveHash);

        // Let Alice reveal
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, NO_OP_MOVE_INDEX, salt, extraData, true);

        // Let Bob both reveal
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, NO_OP_MOVE_INDEX, salt, extraData, true);

        // Turn ID should now be 2
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.turnId, 2);
    }

    function test_fasterSpeedKOsGameOver() public {
        // Initialize mons
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory fastMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 1,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon memory slowMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 1,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory fastTeam = new Mon[](1);
        fastTeam[0] = fastMon;
        Mon[] memory slowTeam = new Mon[](1);
        slowTeam[0] = slowMon;
        teams[0] = fastTeam;
        teams[1] = slowTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        IValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        // (Alice should win because her mon is faster)
        _commitRevealExecuteForAliceAndBob(battleKey, 0, 0, "", "");

        // Assert Alice wins
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);

        // Assert that the staminaDelta was set correctly
        assertEq(state.monStates[0][0].staminaDelta, -1);
    }

    function test_fasterPriorityKOsGameOver() public {
        // Initialize fast and slow mons
        IMoveSet slowAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet fastAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory slowMoves = new IMoveSet[](1);
        slowMoves[0] = slowAttack;
        IMoveSet[] memory fastMoves = new IMoveSet[](1);
        fastMoves[0] = fastAttack;
        Mon memory fastMon = Mon({
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
            moves: slowMoves,
            ability: IAbility(address(0))
        });
        Mon memory slowMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: fastMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory fastTeam = new Mon[](1);
        fastTeam[0] = fastMon;
        Mon[] memory slowTeam = new Mon[](1);
        slowTeam[0] = slowMon;
        teams[0] = fastTeam;
        teams[1] = slowTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        IValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(battleKey, 0, 0, "", "");

        // Assert Bob wins as he has faster priority on a slower mon
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);

        // Assert that the staminaDelta was set correctly for Bob's mon
        assertEq(state.monStates[1][0].staminaDelta, -1);
    }

    function test_timeoutSucceedsCommitPlayerNoSwitchFlag() public {
        bytes32 battleKey = _startDummyBattle();

        // Wait for TIMEOUT_DURATION + 1
        vm.warp(TIMEOUT_DURATION + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Bob wins bc Alice didn't commit to start
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_timeoutSucceedsRevealPlayerNoSwitchFlag() public {
        bytes32 battleKey = _startDummyBattle();

        // Let Alice commit to choosing switch
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, moveHash);

        // Wait for TIMEOUT_DURATION + 1
        vm.warp(TIMEOUT_DURATION + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Alice wins because Bob didn't reveal
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);
    }

    function test_timeoutSucceedsCommitPlayerWitholdsRevealNoSwitchFlag() public {
        bytes32 battleKey = _startDummyBattle();

        // Let Alice commit to choosing switch
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, moveHash);

        // Let Bob reveal to choosing switch as well
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Wait for TIMEOUT_DURATION + 1
        vm.warp(TIMEOUT_DURATION + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Bob wins because Alice didn't reveal
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_timeoutScceedsRevealPlayerSwitchFlag() public {
        // Initialize fast and slow mons
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory fastMon = Mon({
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
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon memory slowMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[] memory fastTeam = new Mon[](2);
        fastTeam[0] = fastMon;
        fastTeam[1] = fastMon;
        Mon[] memory slowTeam = new Mon[](2);
        slowTeam[0] = slowMon;
        slowTeam[1] = slowMon;
        // Register teams
        defaultRegistry.setTeam(ALICE, fastTeam);
        defaultRegistry.setTeam(BOB, slowTeam);

        IValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(battleKey, 0, 0, "", "");

        // Alice should knock out Bob, but let Bob do nothing
        // Skip ahead TIMEOUT_DURATION + 1
        vm.warp(TIMEOUT_DURATION + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Alice wins because Bob didn't reveal
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);
    }

    function test_secondBattleDifferentBattleKey() public {
        bytes32 battleKey = _startDummyBattle();
        vm.warp(TIMEOUT_DURATION + 1);
        vm.startPrank(BOB);
        engine.end(battleKey);
        bytes32 newBattleKey = _startDummyBattle();
        assertNotEq(battleKey, newBattleKey);
    }
}
