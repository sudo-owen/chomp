// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {DefaultRuleset} from "../src/DefaultRuleset.sol";

import {DefaultCommitManager} from "../src/DefaultCommitManager.sol";
import {Engine} from "../src/Engine.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

import {IEffect} from "../src/effects/IEffect.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";

import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {CustomAttack} from "./mocks/CustomAttack.sol";

import {AfterDamageReboundEffect} from "./mocks/AfterDamageReboundEffect.sol";
import {EffectAbility} from "./mocks/EffectAbility.sol";
import {EffectAttack} from "./mocks/EffectAttack.sol";
import {ForceSwitchMove} from "./mocks/ForceSwitchMove.sol";
import {GlobalEffectAttack} from "./mocks/GlobalEffectAttack.sol";
import {InstantDeathEffect} from "./mocks/InstantDeathEffect.sol";
import {InstantDeathOnSwitchInEffect} from "./mocks/InstantDeathOnSwitchInEffect.sol";
import {InvalidMove} from "./mocks/InvalidMove.sol";
import {MockRandomnessOracle} from "./mocks/MockRandomnessOracle.sol";

import {IEngineHook} from "../src/IEngineHook.sol";

import {OneTurnStatBoost} from "./mocks/OneTurnStatBoost.sol";
import {SingleInstanceEffect} from "./mocks/SingleInstanceEffect.sol";
import {SkipTurnMove} from "./mocks/SkipTurnMove.sol";
import {TempStatBoostEffect} from "./mocks/TempStatBoostEffect.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";

import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";
import {BattleHelper} from "./abstract/BattleHelper.sol";
import {TestTypeCalculator} from "./mocks/TestTypeCalculator.sol";

contract EngineTest is Test, BattleHelper {
    DefaultCommitManager commitManager;
    Engine engine;
    FastValidator validator;
    ITypeCalculator typeCalc;
    DefaultRandomnessOracle defaultOracle;
    TestTeamRegistry defaultRegistry;
    DefaultMatchmaker matchmaker;

    uint256 constant TIMEOUT_DURATION = 100;
    address constant CARL = address(3);

    Mon dummyMon;
    IMoveSet dummyAttack;

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new DefaultCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        typeCalc = new TestTypeCalculator();
        dummyAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 0, ACCURACY: 0, STAMINA_COST: 0, PRIORITY: 0})
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = dummyAttack;
        dummyMon = Mon({
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
        defaultRegistry = new TestTeamRegistry();
        matchmaker = new DefaultMatchmaker(engine);
    }

    // Helper function, creates a battle with two mons for Alice and Bob
    function _startDummyBattle() internal returns (bytes32) {
        Mon[][] memory dummyTeams = new Mon[][](2);
        Mon[] memory dummyTeam = new Mon[](1);
        dummyTeam[0] = dummyMon;
        dummyTeams[0] = dummyTeam;
        dummyTeams[1] = dummyTeam;

        // Register teams
        defaultRegistry.setTeam(ALICE, dummyTeams[0]);
        defaultRegistry.setTeam(BOB, dummyTeams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        return battleKey;
    }

    function test_canStartBattleBothPlayersNoOpAfterSwap() public {
        bytes32 battleKey = _startDummyBattle();

        // Let Alice and Bob both commit to switching
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob do a no-op
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

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

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        // (Alice should win because her mon is faster)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

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

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Assert Bob wins as he has faster priority on a slower mon
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);

        // Assert that the staminaDelta was set correctly for Bob's mon
        assertEq(state.monStates[1][0].staminaDelta, -1);
    }

    function _setup2v2FasterPriorityBattleAndForceSwitch() internal returns (bytes32) {
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
        Mon[] memory fastTeam = new Mon[](2);
        fastTeam[0] = fastMon;
        fastTeam[1] = fastMon;
        Mon[] memory slowTeam = new Mon[](2);
        slowTeam[0] = slowMon;
        slowTeam[1] = slowMon;
        teams[0] = fastTeam;
        teams[1] = slowTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // End result is Bob KO's Alice's mon (wins on priority even though lower speed), so Alice now needs to switch

        return battleKey;
    }

    function test_fasterPriorityKOsForcesSwitch() public {
        bytes32 battleKey = _setup2v2FasterPriorityBattleAndForceSwitch();

        // Check that Alice (p0) now has the playerSwitch flag set
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);

        // Assert that Bob cannot commit anything because of the turn flag
        // (we just reuse Alice's move hash bc it doesn't matter)
        vm.startPrank(BOB);
        vm.expectRevert(DefaultCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMove(battleKey, bytes32(0));

        // Reveal Alice's move, and advance game state
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, bytes32(""), abi.encode(1), false);
        engine.execute(battleKey);

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Assert Bob wins as he has faster priority on a slower mon
        state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);

        // Assert that the staminaDelta was set correctly for Bob's mon
        // (we used two attacks of 1 stamina, so -2)
        assertEq(state.monStates[1][0].staminaDelta, -2);
    }

    function test_fasterPriorityKOsForcesSwitchCorrectlyFailsOnInvalidSwitchReveal() public {
        bytes32 battleKey = _setup2v2FasterPriorityBattleAndForceSwitch();

        // Check that Alice (p0) now has the playerSwitch flag set
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);

        // Alice now switches (invalidly) to mon index 0
        // Attempt to reveal Alice's move, and assert that we cannot advance the game state
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", ALICE));
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, bytes32(""), abi.encode(0), false);

        // Attempt to forcibly advance the game state
        vm.expectRevert();
        engine.execute(battleKey);

        // Check that timeout succeeds for Bob in this case
        vm.warp((TIMEOUT_DURATION * validator.PREV_TURN_MULTIPLIER()) + 1);
        engine.end(battleKey);

        // Assert Bob wins
        state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_fasterPriorityKOsForcesSwitchCorrectlyFailsOnInvalidSwitchNoCommit() public {
        bytes32 battleKey = _setup2v2FasterPriorityBattleAndForceSwitch();

        // Check that Alice (p0) now has the playerSwitch flag set
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);

        // Attempt to forcibly advance the game state
        vm.expectRevert();
        engine.execute(battleKey);

        // Assume Alice AFKs

        // Check that timeout succeeds for Bob in this case, Alice is the loser
        vm.warp((TIMEOUT_DURATION * validator.PREV_TURN_MULTIPLIER()) + 1);
        engine.end(battleKey);

        // Assert Bob wins
        state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_nonKOSubsequentMoves() public {
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2, // need to have enough stamina for 2 moves
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
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](1);
        team[0] = normalMon;
        teams[0] = team;
        teams[1] = team;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        // (No mons are knocked out yet)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Let Alice and Bob commit and reveal to both choosing attack again
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Both Alice and Bob's mons have the same speed, so the final priority player is rng % 2
        BattleState memory state = engine.getBattleState(battleKey);
        uint256 finalRNG = state.pRNGStream[state.pRNGStream.length - 1];
        uint256 winnerIndex = finalRNG % 2;
        if (winnerIndex == 0) {
            assertEq(state.winner, ALICE);
        } else {
            assertEq(state.winner, BOB);
        }

        // Assert that the staminaDelta was set correctly (2 moves spent) for the winning mon
        assertEq(state.monStates[winnerIndex][0].staminaDelta, -2);
    }

    function test_switchPriorityIsFasterThanMove() public {
        // Initialize mons and moves
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        teams[0] = team;
        teams[1] = team;
        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Second move, have Alice swap out to mon at index 1, have Bob use attack
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Assert that mon index for Alice is 1
        // Assert that the mon state for Alice has -5 applied to the switched in mon
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[0], 1);
        assertEq(state.monStates[0][1].hpDelta, -5);
    }

    function test_switchPriorityIsSlowerThanSuperfastMove() public {
        // Initialize mons and moves
        IMoveSet superFastAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = superFastAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        teams[0] = team;
        teams[1] = team;
        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Second move, have Alice swap out to mon at index 1, have Bob use fast attack
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Assert that mon index for Alice is 1
        // Assert that the mon state for Alice has -5 applied to the previous mon
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[0], 1);
        assertEq(state.monStates[0][0].hpDelta, -5);
    }

    function test_switchPriorityIsSlowerThanSuperfastMoveWithKO() public {
        // Initialize mons and moves
        IMoveSet superFastAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = superFastAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        teams[0] = team;
        teams[1] = team;
        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Second move, have Alice swap out to mon at index 1, have Bob use fast attack which supersedes Switch
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Given that it's a KO (even though Alice chose switch),
        // check that now they have the priority flag again
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);
    }

    function test_defaultStaminaRegenEffect() public {
        // Initialize mons and moves
        IMoveSet superFastAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = superFastAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        teams[0] = team;
        teams[1] = team;
        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        StaminaRegen regen = new StaminaRegen(engine);
        IEffect[] memory effects = new IEffect[](1);
        effects[0] = regen;
        DefaultRuleset rules = new DefaultRuleset(engine, effects);
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(
            twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker, new IEngineHook[](0), rules
        );

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        // (No mons are knocked out yet)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        BattleState memory state = engine.getBattleState(battleKey);

        // Assert that the staminaDelta was set correctly (now back to 0)
        assertEq(state.monStates[0][0].staminaDelta, 0);
    }

    function test_accuracyWorksAsExpectedWithRNG() public {
        // Deploy a custom RNG oracle that returns a fixed value
        MockRandomnessOracle mockOracle = new MockRandomnessOracle();
        mockOracle.setRNG(1);

        // Initialize mons and moves
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet inaccurateAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 1, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory normalMoves = new IMoveSet[](1);
        normalMoves[0] = normalAttack;
        IMoveSet[] memory inaccurateMoves = new IMoveSet[](1);
        inaccurateMoves[0] = inaccurateAttack;
        Mon memory normalMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: normalMoves,
            ability: IAbility(address(0))
        });
        Mon memory inaccurateMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None,
                speed: 2
            }),
            // need to have enough stamina for 2 moves
            moves: inaccurateMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory normalTeam = new Mon[](1);
        normalTeam[0] = normalMon;
        Mon[] memory inaccurateTeam = new Mon[](1);
        inaccurateTeam[0] = inaccurateMon;
        teams[0] = normalTeam;
        teams[1] = inaccurateTeam;

        // Initialize battle with custom rng oracle
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Assert that Bob's move missed (did no damage)
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].hpDelta, 0);

        // Assert that Alice's move did damage
        assertEq(state.monStates[1][0].hpDelta, -5);
    }

    function test_invalidMoveIfStaminaCostTooHigh() public {
        // Initialize mons and moves
        IMoveSet highStaminaAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 2, PRIORITY: 0})
        );
        IMoveSet[] memory highStaminaMoves = new IMoveSet[](1);
        highStaminaMoves[0] = highStaminaAttack;
        IMoveSet normalStaminaAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory normalStaminaMoves = new IMoveSet[](1);
        normalStaminaMoves[0] = normalStaminaAttack;
        Mon memory highStaminaMon = Mon({
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
            moves: highStaminaMoves,
            ability: IAbility(address(0))
        });
        Mon memory normalStaminaMon = Mon({
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
            moves: normalStaminaMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory highStaminaTeam = new Mon[](1);
        highStaminaTeam[0] = highStaminaMon;
        Mon[] memory normalStaminaTeam = new Mon[](1);
        normalStaminaTeam[0] = normalStaminaMon;
        teams[0] = highStaminaTeam;
        teams[1] = normalStaminaTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Commit move index 0 for Bob
        uint256 moveIndex = 0;
        vm.startPrank(BOB);
        bytes32 bobMoveHash = keccak256(abi.encodePacked(moveIndex, bytes32(""), ""));
        commitManager.commitMove(battleKey, bobMoveHash);

        // Assert that Alice cannot reveal anything because of the stamina cost (she has the high stamina cost mon)
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", ALICE));
        commitManager.revealMove(battleKey, moveIndex, bytes32(""), "", false);
    }

    // Ensure that we cannot write to mon state when there is no active execute() call in the call stack
    function test_ensureWritingToStateFailsWhenNotInCallStack() public {
        _startDummyBattle();

        // Updating mon state directly should revert
        vm.startPrank(ALICE);
        vm.expectRevert(Engine.NoWriteAllowed.selector);
        engine.updateMonState(0, 0, MonStateIndexName.Hp, 0);

        // Adding effect directly should revert
        vm.startPrank(ALICE);
        vm.expectRevert(Engine.NoWriteAllowed.selector);
        engine.addEffect(0, 0, IEffect(address(0)), "");

        // Deleting effect directly should revert
        vm.startPrank(ALICE);
        vm.expectRevert(Engine.NoWriteAllowed.selector);
        engine.removeEffect(0, 0, 0);
    }

    function test_effectAppliedByAttackCanKOForGameEnd() public {
        // Initialize mons and moves
        IMoveSet normalStaminaAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalStaminaAttack;
        Mon memory normalMon = Mon({
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
        // Instant death attack
        IEffect instantDeath = new InstantDeathEffect(engine);
        IMoveSet instantDeathAttack =
            new EffectAttack(engine, instantDeath, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory deathMoves = new IMoveSet[](1);
        deathMoves[0] = instantDeathAttack;
        Mon memory instantDeathMon = Mon({
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
            moves: deathMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](1);
        team[0] = normalMon;
        Mon[] memory deathTeam = new Mon[](1);
        deathTeam[0] = instantDeathMon;
        teams[0] = team;
        teams[1] = deathTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, which for Bob afflicts the instant death condition on the
        // opposing mon (Alice's) and knocks it out
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Assert Bob wins
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_effectAppliedByAttackCanKOAndForceSwitch() public {
        // Initialize mons and moves
        IMoveSet normalStaminaAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalStaminaAttack;
        Mon memory normalMon = Mon({
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
        // Instant death attack
        IEffect instantDeath = new InstantDeathEffect(engine);
        IMoveSet instantDeathAttack =
            new EffectAttack(engine, instantDeath, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory deathMoves = new IMoveSet[](1);
        deathMoves[0] = instantDeathAttack;
        Mon memory instantDeathMon = Mon({
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
            moves: deathMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        Mon[] memory deathTeam = new Mon[](2);
        deathTeam[0] = instantDeathMon;
        deathTeam[1] = instantDeathMon;
        teams[0] = team;
        teams[1] = deathTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, which for Bob afflicts the instant death condition on the
        // opposing mon (Alice's) and knocks it out
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Now only Alice should be able to switch
        vm.startPrank(ALICE);

        // Alice should be able to reveal because she is the only player (player flag should be set)
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, bytes32(""), abi.encode(1), false);

        // Execute the switch
        engine.execute(battleKey);
    }

    function test_effectAppliedByAttackCorrectlyAppliesToTargetedMonEvenAfterSwitch() public {
        // Mon that has a temporary stat boost effect
        IEffect statBoost = new OneTurnStatBoost(engine);
        IMoveSet[] memory moves = new IMoveSet[](1);

        // Create new effect attack that applies the temporary stat boost effect
        IMoveSet effectAttack =
            new EffectAttack(engine, statBoost, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        moves[0] = effectAttack;
        Mon memory mon = Mon({
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
        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        FastValidator oneMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(oneMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice swaps to mon index 1, and Bob applies the effect
        // The effect should be applied to mon index 1 for Alice but only during the duration of the turn
        // (We have a check for 2 instead of 1 to avoid confusing it with the base case state)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Assert that the temporary stat boost effect is updated to 2 because the roundEnd hook also runs
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][1].attackDelta, 2);
    }

    function test_moveKOSupersedesRoundEndEffectKOForGameEnd() public {
        // Initialize mons and moves
        IMoveSet lethalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 7})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = lethalAttack;
        Mon memory normalMon = Mon({
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
        // Instant death attack
        IEffect instantDeath = new InstantDeathEffect(engine);
        IMoveSet instantDeathAttack =
            new EffectAttack(engine, instantDeath, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory deathMoves = new IMoveSet[](1);
        deathMoves[0] = instantDeathAttack;
        Mon memory instantDeathMon = Mon({
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
            moves: deathMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](1);
        team[0] = normalMon;
        Mon[] memory deathTeam = new Mon[](1);
        deathTeam[0] = instantDeathMon;
        teams[0] = team;
        teams[1] = deathTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, which for Bob afflicts the instant death condition on the
        // opposing mon (Alice's)
        // But Alice's mon should KO Bob's before the end of round takes place
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Assert Alice wins
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);
    }

    function test_moveKOAndEffectKOLeadToDualSwapOtherMoveRevertsForAlice() public {
        // Initialize mons and moves
        IMoveSet lethalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = lethalAttack;
        Mon memory normalMon = Mon({
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
        // Instant death attack
        IEffect instantDeath = new InstantDeathEffect(engine);
        IMoveSet instantDeathAttack =
            new EffectAttack(engine, instantDeath, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory deathMoves = new IMoveSet[](1);
        deathMoves[0] = instantDeathAttack;
        Mon memory instantDeathMon = Mon({
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
            moves: deathMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        Mon[] memory deathTeam = new Mon[](2);
        deathTeam[0] = instantDeathMon;
        deathTeam[1] = instantDeathMon;
        teams[0] = team;
        teams[1] = deathTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, which for Bob afflicts the instant death condition on the
        // opposing mon (Alice's) and knocks it out
        // But Bob moves first (higher priority), so he gets the instant death affliction
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Now if Alice tries to pick a non-switch move, the engine should revert
        vm.startPrank(ALICE);
        bytes32 salt = "";
        uint256 aliceMoveIndex = 0;
        bytes32 aliceMoveHash = keccak256(abi.encodePacked(aliceMoveIndex, salt, extraData));
        commitManager.commitMove(battleKey, aliceMoveHash);

        // Bob reveals a swap
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(1), false);

        // Alice's reveal will revert (must choose switch)
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", ALICE));
        commitManager.revealMove(battleKey, aliceMoveIndex, salt, extraData, false);
    }

    function test_moveKOAndEffectKOLeadToDualSwapAndSwapSucceeds() public {
        // Initialize mons and moves
        IMoveSet lethalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = lethalAttack;
        Mon memory normalMon = Mon({
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
        // Instant death attack
        IEffect instantDeath = new InstantDeathEffect(engine);
        IMoveSet instantDeathAttack =
            new EffectAttack(engine, instantDeath, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory deathMoves = new IMoveSet[](1);
        deathMoves[0] = instantDeathAttack;
        Mon memory instantDeathMon = Mon({
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
            moves: deathMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](2);
        team[0] = normalMon;
        team[1] = normalMon;
        Mon[] memory deathTeam = new Mon[](2);
        deathTeam[0] = instantDeathMon;
        deathTeam[1] = instantDeathMon;
        teams[0] = team;
        teams[1] = deathTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, which for Bob afflicts the instant death condition on the
        // opposing mon (Alice's) and knocks it out
        // But Bob moves first (higher priority), so he gets the instant death affliction
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Now both moves have to swap to index 1 for their mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(1), abi.encode(1)
        );
    }

    function test_shouldSkipTurnFlagWorks() public {
        // Initialize mons and moves
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 6})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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
        // Skip Turn attack to skip move
        IMoveSet skipAttack =
            new SkipTurnMove(engine, SkipTurnMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 7}));
        IMoveSet[] memory skipMoves = new IMoveSet[](1);
        skipMoves[0] = skipAttack;
        Mon memory skipMon = Mon({
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
            moves: skipMoves,
            ability: IAbility(address(0))
        });
        Mon[][] memory teams = new Mon[][](2);
        Mon[] memory team = new Mon[](1);
        team[0] = normalMon;
        Mon[] memory skipTeam = new Mon[](1);
        skipTeam[0] = skipMon;
        teams[0] = team;
        teams[1] = skipTeam;
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0
        // Bob goes for a fast skip turn effect
        // Alice tries to go fast for a lethal effect
        // Bob should win priority and inflict skip turn effect
        uint256 moveIndex = 0;
        bytes memory extraData = "";
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, moveIndex, moveIndex, extraData, extraData);

        // Assert no winner, and no damage dealt
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, address(0));
        assertEq(state.monStates[1][0].hpDelta, 0);
    }

    function test_forceSwitchMoveCorrectlySwitchesNonPriorityPlayerEndOfRound() public {
        // Initialize mons and moves
        // Attack to force a switch (should be lower priority than the other move)
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 0}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        Mon[] memory team = new Mon[](2);
        team[0] = switchMon;
        team[1] = switchMon;

        Mon[] memory otherTeam = new Mon[](2);
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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
        otherTeam[0] = normalMon;
        otherTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, but Alice encodes a swap to mon index 1 for player index 1 (Bob)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, abi.encode(1, 1), "");

        // Verify that Bob's mon is now index 1
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[1], 1);

        // Verify that Alice's mon took damage
        assertEq(state.monStates[0][0].hpDelta, -5);
    }

    function test_forceSwitchMoveCorrectlySwitchesPriorityPlayerAfterAttacking() public {
        // Initialize mons and moves
        // Attack to force a switch for user (should be higher priority than the other move)
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = switchMon;
        team[1] = switchMon;
        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = normalMon;
        otherTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Both player pick move index 0, but Alice encodes a swap to mon index 1 for player index 0 (Alice)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, abi.encode(0, 1), "");

        // Assert that Alice's mon is now index 1
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[0], 1);

        // Assert that Alice's new mon took damage
        assertEq(state.monStates[0][1].hpDelta, -5);
    }

    function test_forceSwitchMoveIgnoresInvalidSwitchTargetPriorityPlayerAfterAttacking() public {
        // Initialize mons and moves
        // Attack to force a switch for user (should be higher priority than the other move)
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = switchMon;
        team[1] = switchMon;
        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = normalMon;
        otherTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Bob commit and reveal to attack (move index 0)
        bytes memory extraData = "";
        bytes32 salt = "";
        uint256 moveIndex = 0;
        vm.startPrank(BOB);
        commitManager.commitMove(battleKey, keccak256(abi.encodePacked(moveIndex, salt, extraData)));

        // Let Alice commit to switching to mon index 0 (invalid target) with player index 0 (herself)
        // Alice can now reveal, but the switchActiveMon call inside ForceSwitchMove will revert
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, moveIndex, salt, abi.encode(0, 0), false);

        // Ensure Bob can reveal
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, moveIndex, salt, extraData, false);

        // Execute the battle - the invalid switch should be ignored
        engine.execute(battleKey);

        // Check that the active mon index for Alice is still 0 (no switch happened)
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[0], 0);
    }

    function test_forceSwitchMoveIgnoresInvalidSwitchTargetNonPriorityPlayerAfterAttacking() public {
        // Initialize mons and moves
        // Attack to force a switch for user (should be higher priority than the other move)
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = switchMon;
        team[1] = switchMon;
        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = normalMon;
        otherTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Bob commit and reveal to attack (move index 0)
        bytes memory extraData = "";
        bytes32 salt = "";
        uint256 moveIndex = 0;
        vm.startPrank(BOB);
        commitManager.commitMove(battleKey, keccak256(abi.encodePacked(moveIndex, salt, extraData)));

        // Alice can now reveal, but the switchActiveMon call inside ForceSwitchMove will revert
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, 0, salt, abi.encode(1, 0), false);

        // Ensure Bob can reveal
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, moveIndex, salt, extraData, false);

        // Execute the battle - the invalid switch should be ignored
        engine.execute(battleKey);

        // Check that the active mon index for Alice is still 0 (no switch happened)
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.activeMonIndex[0], 0);
    }

    // environmental effect kills mon after switch in from player move and forces switch
    function test_effectOnSwitchInFromSwitchMoveKOsAndForcesSwitch() public {
        // Initialize mons and moves
        // Attack to force a switch for user (should be higher priority than the other move)
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });

        // Create a new GlobalEffectAttack that applies InstantDeathOnSwitchIn
        IEffect instantDeathOnSwitchIn = new InstantDeathOnSwitchInEffect(engine);

        // Move should be higher priority than the switch attack
        IMoveSet instantDeathOnSwitchInAttack = new GlobalEffectAttack(
            engine, instantDeathOnSwitchIn, GlobalEffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = instantDeathOnSwitchInAttack;
        Mon memory stageHazardMon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = switchMon;
        team[1] = switchMon;
        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = stageHazardMon;
        otherTeam[1] = stageHazardMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let both players select move index 0
        // (Have Alice force themselves to switch to mon index 1)
        // (But swapping to mon index 1 will trigger on switch in and kill the mon)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, abi.encode(0, 1), "");

        // Assert that the player switch for turn flag is now 0, indicating Alice has to switch
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);

        // Assert that Alice's new mon is now KOed
        assertEq(state.monStates[0][1].isKnockedOut, true);
    }

    // environmental effect kills mon after switch in from other player move and forces switch
    function test_effectOnSwitchInFromSwitchMoveForOtherPlayerKOsAndForcesSwitch() public {
        // Initialize mons and moves
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IEffect instantDeathOnSwitchIn = new InstantDeathOnSwitchInEffect(engine);
        IMoveSet instantDeathOnSwitchInAttack = new GlobalEffectAttack(
            engine, instantDeathOnSwitchIn, GlobalEffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2})
        );

        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = switchAttack;
        moves[1] = instantDeathOnSwitchInAttack;

        Mon memory mon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = mon;
        otherTeam[1] = mon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 2, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // (Have Alice force Bob to switch to mon index 1, have Bob select the instant death switch in effect
        // (But swapping to mon index 1 will trigger on switch in and kill the mon)
        // Instant death on switch in (by Bob's mon) will trigger and kill his own mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 1, abi.encode(1, 1), "");

        // Assert that the player switch for turn flag is now 0, indicating Bob has to switch
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 1);

        // Assert that Bob's new mon is now KOed
        assertEq(state.monStates[1][1].isKnockedOut, true);
    }

    // environmental effect kills mon after switch in move (not as a side effect from move)
    function test_effectOnSwitchInFromDirectSwitchMoveKOsAndForcesSwitch() public {
        // Initialize mons and moves
        IEffect instantDeathOnSwitchIn = new InstantDeathOnSwitchInEffect(engine);

        // Set priority to be higher than switch
        IMoveSet instantDeathOnSwitchInAttack = new GlobalEffectAttack(
            engine, instantDeathOnSwitchIn, GlobalEffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 10})
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = instantDeathOnSwitchInAttack;

        Mon memory mon = Mon({
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

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        Mon[] memory otherTeam = new Mon[](2);
        otherTeam[0] = mon;
        otherTeam[1] = mon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = otherTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Have Alice switch to their second mon, have Bob select the instant death switch in effect
        // (But swapping to mon index 1 for Alice will trigger on switch in and kill the mon)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Assert that the player switch for turn flag is now 0, indicating Alice has to switch
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.playerSwitchForTurnFlag, 0);

        // Assert that Alice's new mon is now KOed
        assertEq(state.monStates[0][1].isKnockedOut, true);
    }

    // ability triggers effect leading to death on self after switch-in (lol)
    function test_abilityOnSwitchInKOsAndLeadsToGameOver() public {
        // Initialize mons and moves
        IMoveSet[] memory moves = new IMoveSet[](0);
        IEffect instantDeathAtEndOfTurn = new InstantDeathEffect(engine);
        IAbility suicideAbility = new EffectAbility(engine, instantDeathAtEndOfTurn);
        Mon memory suicideMon = Mon({
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
            ability: suicideAbility
        });
        Mon memory normalMon = Mon({
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
        Mon[] memory suicideTeam = new Mon[](1);
        suicideTeam[0] = suicideMon;
        Mon[] memory normalTeam = new Mon[](1);
        normalTeam[0] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = suicideTeam;
        teams[1] = normalTeam;

        FastValidator oneMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(oneMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // After this, Alice's mon should be dead and Bob should be the winner
        // Verify Bob is the winner
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    // ability triggers effect leading to death on self after being switched in from self move
    function test_abilityOnSwitchInFromSwitchInMoveKOsAndLeadsToGameOver() public {
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        IEffect instantDeathAtEndOfTurn = new InstantDeathEffect(engine);
        IAbility suicideAbility = new EffectAbility(engine, instantDeathAtEndOfTurn);
        Mon memory suicideMon = Mon({
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
            moves: switchMoves,
            ability: suicideAbility
        });

        // A normal mon with a damaging move
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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

        Mon[] memory suicideTeam = new Mon[](2);
        suicideTeam[0] = switchMon;
        suicideTeam[1] = suicideMon;

        Mon[] memory normalTeam = new Mon[](2);
        normalTeam[0] = normalMon;
        normalTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = suicideTeam;
        teams[1] = normalTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice switches themselves to mon index 1, while Bob chooses move index 0
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, abi.encode(0, 1), "");

        // Assert that Alice's new mon is now KOed
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][1].isKnockedOut, true);

        // Assert that player switch flag for turn is now 0, indicating Alice has to switch
        assertEq(state.playerSwitchForTurnFlag, 0);
    }

    // ability triggers effect from a manual switch
    function test_abilityOnSwitchInFromManualSwitchKOsAndLeadsToGameOver() public {
        IMoveSet switchAttack =
            new ForceSwitchMove(engine, ForceSwitchMove.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 2}));
        IMoveSet[] memory switchMoves = new IMoveSet[](1);
        switchMoves[0] = switchAttack;
        Mon memory switchMon = Mon({
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
            moves: switchMoves,
            ability: IAbility(address(0))
        });
        IEffect instantDeathAtEndOfTurn = new InstantDeathEffect(engine);
        IAbility suicideAbility = new EffectAbility(engine, instantDeathAtEndOfTurn);
        Mon memory suicideMon = Mon({
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
            moves: switchMoves,
            ability: suicideAbility
        });

        // A normal mon with a damaging move
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = normalAttack;
        Mon memory normalMon = Mon({
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

        Mon[] memory suicideTeam = new Mon[](2);
        suicideTeam[0] = switchMon;
        suicideTeam[1] = suicideMon;

        Mon[] memory normalTeam = new Mon[](2);
        normalTeam[0] = normalMon;
        normalTeam[1] = normalMon;

        Mon[][] memory teams = new Mon[][](2);
        teams[0] = suicideTeam;
        teams[1] = normalTeam;

        FastValidator twoMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(twoMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice switches themselves to mon index 1, while Bob chooses move index 0
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Assert that Alice's new mon is now KOed
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][1].isKnockedOut, true);

        // Assert that player switch flag for turn is now 0, indicating Alice has to switch
        assertEq(state.playerSwitchForTurnFlag, 0);
    }

    // attack that applies effect can only apply once (checks using an effect that writes to global KV)
    function test_attackThatAppliesEffectCanOnlyApplyOnce() public {
        // Single instance effect
        IEffect singleInstanceEffect = new SingleInstanceEffect(engine);
        IMoveSet effectAttack = new EffectAttack(
            engine, singleInstanceEffect, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1})
        );
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = effectAttack;
        Mon memory mon = Mon({
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
        Mon[] memory team = new Mon[](1);
        team[0] = mon;
        Mon[][] memory teams = new Mon[][](2);
        teams[0] = team;
        teams[1] = team;

        FastValidator oneMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, teams[0]);
        defaultRegistry.setTeam(BOB, teams[1]);

        bytes32 battleKey = _startBattle(oneMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice and Bob both select attacks (they should apply the single instance effect on hit)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Alice and Bob again both select attacks again
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Assert that the effect was only applied once
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].targetedEffects.length, 1);
        assertEq(state.monStates[1][0].targetedEffects.length, 1);
    }

    function test_moveSpecificInvalidFlagsAreCheckedDuringReveal() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        IMoveSet invalidMove = new InvalidMove(engine);
        moves[0] = invalidMove;
        Mon memory mon = Mon({
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
        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob commits to NO_OP
        vm.startPrank(BOB);
        uint256 moveIndex = NO_OP_MOVE_INDEX;
        bytes32 bobMoveHash = keccak256(abi.encodePacked(moveIndex, bytes32(""), ""));
        commitManager.commitMove(battleKey, bobMoveHash);

        // Alice should revert when revealing
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("InvalidMove(address)", ALICE));
        commitManager.revealMove(battleKey, 0, bytes32(""), "", false);
    }

    function test_onMonSwitchOutHookWorksWithTempStatBoost() public {
        // Mon that has a temporary stat boost effect
        IEffect temporaryStatBoostEffect = new TempStatBoostEffect(engine);
        IMoveSet[] memory moves = new IMoveSet[](1);

        // Create new effect attack that applies the temporary stat boost effect
        IMoveSet effectAttack = new EffectAttack(
            engine, temporaryStatBoostEffect, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1})
        );
        moves[0] = effectAttack;
        Mon memory mon = Mon({
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
        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        FastValidator oneMonValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(oneMonValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice and Bob both select attacks (they should apply the temporary stat boost effect)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Assert that the temporary stat boost effect was applied to both mons
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].attackDelta, 1);
        assertEq(state.monStates[1][0].attackDelta, 1);

        // Alice and Bob both switch to mon index 1
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(1), abi.encode(1)
        );

        // Assert that the temporary stat boost effect was removed from both mons
        state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][1].attackDelta, 0);
        assertEq(state.monStates[1][1].attackDelta, 0);
    }

    function test_afterDamageHookRuns() public {
        // Create an attack that adds the rebound effect to the caller
        IEffect reboundEffect = new AfterDamageReboundEffect(engine);
        IMoveSet[] memory moves = new IMoveSet[](2);
        IMoveSet reboundAttack =
            new EffectAttack(engine, reboundEffect, EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        moves[0] = reboundAttack;
        IMoveSet normalAttack = new CustomAttack(
            engine,
            typeCalc,
            CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 5, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        moves[1] = normalAttack;

        Mon memory mon = Mon({
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

        // Create both teams (teams of length 1)
        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        // Create 2 move, 1 mon validator
        FastValidator twoMoveValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        bytes32 battleKey = _startBattle(twoMoveValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice and Bob both select attacks, both of them are move index 0 (do damage rebound)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Alice and Bob both select attacks, both of them are move index 1 (normal attack)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 1, 1, "", "");
        BattleState memory state = engine.getBattleState(battleKey);

        // Assert that the rebound effect was applied to both mons
        // (both have done no damage now)
        assertEq(state.monStates[0][0].hpDelta, 0);
        assertEq(state.monStates[1][0].hpDelta, 0);
    }

    function test_doubleCommitOrDoubleRevealReverts() public {
        IMoveSet[] memory moves = new IMoveSet[](0);
        Mon memory mon = Mon({
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

        // Create both teams (teams of length 1)
        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        // Create 0 move, 2 mon validator
        FastValidator twoMoveValidator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 0, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Start battle
        bytes32 battleKey = _startBattle(twoMoveValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // Alice commits to swapping in mon index 1
        bytes32 salt = "";
        bytes32 aliceMoveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, abi.encode(1)));
        vm.startPrank(ALICE);
        commitManager.commitMove(battleKey, aliceMoveHash);

        // Alice cannot commit again
        vm.expectRevert(DefaultCommitManager.AlreadyCommited.selector);
        commitManager.commitMove(battleKey, aliceMoveHash);

        // Bob reveals
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(1), false);

        // Bob cannot reveal twice
        vm.expectRevert(DefaultCommitManager.AlreadyRevealed.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(1), false);

        // Alice reveals but does not execute
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(1), false);

        // Second reveal should also fail
        vm.expectRevert(DefaultCommitManager.AlreadyRevealed.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, abi.encode(1), false);
    }

    function test_cannotCommitToEndedBattle() public {
        IMoveSet[] memory empty = new IMoveSet[](0);
        Mon memory mon = Mon({
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
            moves: empty,
            ability: IAbility(address(0))
        });
        Mon[] memory team = new Mon[](1);
        team[0] = mon;
        // Register teams
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        FastValidator noMoveValidator =
            new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 0, TIMEOUT_DURATION: 0}));
        bytes32 battleKey = _startBattle(noMoveValidator, engine, defaultOracle, defaultRegistry, matchmaker);

        // Both players send in mon index 0
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob does nothing (it's his turn to move, so he'll lose by timeout)

        // Skip ahead 1 second (past the timeout)
        vm.warp(block.timestamp + 1);

        // End the battle
        engine.end(battleKey);

        // Check that ALICE wins (Bob didn't commit for round 2)
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);

        // // Bob should not be able to commit to the ended battle
        vm.startPrank(BOB);
        vm.expectRevert(DefaultCommitManager.BattleAlreadyComplete.selector);
        commitManager.commitMove(battleKey, bytes32(0));
    }

    // Helper function, creates a battle with two mons each for Alice and Bob
    function _startDummyBattleWithTwoMons() internal returns (bytes32) {
        IMoveSet[] memory moves = new IMoveSet[](1);
        Mon memory dummyMon2 = Mon({
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
        dummyTeam[0] = dummyMon2;
        dummyTeam[1] = dummyMon2;

        // Register teams
        defaultRegistry.setTeam(ALICE, dummyTeam);
        defaultRegistry.setTeam(BOB, dummyTeam);

        // Set up validatorToUse
        FastValidator validatorToUse = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        // Setup battle
        bytes32 battleKey = _startBattle(validatorToUse, engine, defaultOracle, defaultRegistry, matchmaker);

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

    function test_anyoneCanFillP1() public {
        // Create validatorToUse with zero mons and zero moves needed
        FastValidator validatorToUse = new FastValidator(
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

        // Authorize matchmaker
        vm.startPrank(ALICE);
        address[] memory makersToAdd = new address[](1);
        makersToAdd[0] = address(matchmaker);
        address[] memory makersToRemove = new address[](0);
        engine.updateMatchmakers(makersToAdd, makersToRemove);
        vm.startPrank(BOB);
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        // Create a battle with Alice as p0 and zero address as p1
        vm.startPrank(ALICE);
        bytes32 salt = "";
        uint96 p0TeamIndex = 0;
        uint256[] memory p0TeamIndices = defaultRegistry.getMonRegistryIndicesForTeam(ALICE, p0TeamIndex);
        bytes32 p0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));
        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: p0TeamHash,
            p1: address(0),
            p1TeamIndex: 0,
            teamRegistry: defaultRegistry,
            validator: validatorToUse,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            engineHooks: new IEngineHook[](0),
            moveManager: IMoveManager(address(0)),
            matchmaker: matchmaker
        });
        bytes32 battleKey = matchmaker.proposeBattle(proposal);
        vm.startPrank(BOB);
        // Set battleKey to be updated battle key
        battleKey = matchmaker.acceptBattle(battleKey, 0, matchmaker.getBattleProposalIntegrityHash(proposal));
        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);

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
    function test_turn0DefaultCommitManagerValidPreimage() public {
        bytes32 battleKey = _startDummyBattleWithTwoMons();
        bytes32 salt = "";
        bytes memory extraData = abi.encode(0);
        bytes32 moveHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, salt, extraData));

        // Ensure Alice cannot reveal yet because Alice has not yet committed
        // It is turn 0, so Alice must first commit then reveal
        // We will attempt to calculate the preimage, which will fail
        vm.startPrank(ALICE);
        vm.expectRevert(DefaultCommitManager.WrongPreimage.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Bob cannot commit as they only need to reveal
        vm.startPrank(BOB);
        vm.expectRevert(DefaultCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Bob cannot reveal yet as Alice has not committed
        vm.expectRevert(DefaultCommitManager.RevealBeforeOtherCommit.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Carl cannot commit as they are not in the battle
        vm.startPrank(CARL);
        vm.expectRevert(DefaultCommitManager.NotP0OrP1.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Carl should also be unable to reveal
        vm.expectRevert(DefaultCommitManager.NotP0OrP1.selector);
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
    function test_turn0DefaultCommitManagerInvalidPreimage() public {
        bytes32 battleKey = _startDummyBattleWithTwoMons();

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
        vm.expectRevert(DefaultCommitManager.WrongPreimage.selector);
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
        vm.expectRevert(DefaultCommitManager.WrongPreimage.selector);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, salt, extraData, true);

        // Ensure Alice cannot commit as they only need to reveal
        vm.startPrank(ALICE);
        vm.expectRevert(DefaultCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMove(battleKey, moveHash);

        // Alice cannot reveal yet as Bob has not committed
        vm.expectRevert(DefaultCommitManager.RevealBeforeOtherCommit.selector);
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

    function test_timeoutSucceedsCommitPlayerNoSwitchFlag() public {
        bytes32 battleKey = _startDummyBattleWithTwoMons();

        // Wait for TIMEOUT_DURATION * PREV_TURN_MULTIPLIER + 1
        FastValidator validatorToUse = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        vm.warp(TIMEOUT_DURATION * validatorToUse.PREV_TURN_MULTIPLIER() + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Bob wins bc Alice didn't commit to start
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, BOB);
    }

    function test_timeoutSucceedsRevealPlayerNoSwitchFlag() public {
        bytes32 battleKey = _startDummyBattleWithTwoMons();

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
        bytes32 battleKey = _startDummyBattleWithTwoMons();

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

        FastValidator validatorToUse = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, defaultOracle, defaultRegistry, matchmaker);

        // First move of the game has to be selecting their mons (both index 0)
        _commitRevealExecuteForAliceAndBob(
            battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Let Alice and Bob commit and reveal to both choosing attack (move index 0)
        _commitRevealExecuteForAliceAndBob(battleKey, 0, 0, "", "");

        // Alice should knock out Bob, but let Bob do nothing
        // Skip ahead TIMEOUT_DURATION * multiplier (as it's a new turn)
        vm.warp((TIMEOUT_DURATION * validatorToUse.PREV_TURN_MULTIPLIER()) + 1);

        // Call end on the battle
        engine.end(battleKey);

        // Assert that Alice wins because Bob didn't reveal
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.winner, ALICE);
    }

    function test_secondBattleDifferentBattleKey() public {
        bytes32 battleKey = _startDummyBattleWithTwoMons();
        vm.warp(TIMEOUT_DURATION + 1);
        vm.startPrank(BOB);
        engine.end(battleKey);
        bytes32 newBattleKey = _startDummyBattleWithTwoMons();
        assertNotEq(battleKey, newBattleKey);
    }
}
