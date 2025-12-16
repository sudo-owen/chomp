// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Structs.sol";
import {Test} from "forge-std/Test.sol";

import {DefaultCommitManager} from "../../src/DefaultCommitManager.sol";
import {Engine} from "../../src/Engine.sol";
import {MonStateIndexName, MoveClass, Type} from "../../src/Enums.sol";
import {DefaultValidator} from "../../src/DefaultValidator.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {StatBoosts} from "../../src/effects/StatBoosts.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";
import {BattleHelper} from "../abstract/BattleHelper.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";
import {Baselight} from "../../src/mons/iblivion/Baselight.sol";
import {Brightback} from "../../src/mons/iblivion/Brightback.sol";
import {UnboundedStrike} from "../../src/mons/iblivion/UnboundedStrike.sol";
import {Loop} from "../../src/mons/iblivion/Loop.sol";
import {Renormalize} from "../../src/mons/iblivion/Renormalize.sol";

contract IblivionTest is Test, BattleHelper {
    Engine engine;
    DefaultCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    DefaultValidator validator;
    StatBoosts statBoost;
    StandardAttackFactory attackFactory;
    DefaultMatchmaker matchmaker;

    // Iblivion contracts
    Baselight baselight;
    Brightback brightback;
    UnboundedStrike unboundedStrike;
    Loop loop;
    Renormalize renormalize;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 4, TIMEOUT_DURATION: 10})
        );
        commitManager = new DefaultCommitManager(IEngine(address(engine)));
        statBoost = new StatBoosts(IEngine(address(engine)));
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
        matchmaker = new DefaultMatchmaker(engine);

        // Deploy Iblivion contracts
        baselight = new Baselight(IEngine(address(engine)));
        brightback = new Brightback(IEngine(address(engine)), ITypeCalculator(address(typeCalc)), baselight);
        unboundedStrike = new UnboundedStrike(IEngine(address(engine)), ITypeCalculator(address(typeCalc)), baselight);
        loop = new Loop(IEngine(address(engine)), baselight, statBoost);
        renormalize = new Renormalize(IEngine(address(engine)), baselight, statBoost, loop);
    }

    // ============ Baselight Ability Tests ============

    function test_baselightStartsAtOneOnFirstSwitchIn() public {
        // Create a mon with Baselight ability
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = mon;
        aliceTeam[1] = mon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = mon;
        bobTeam[1] = mon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Check that Baselight level is 1 (turn 0 doesn't increment)
        uint256 baselightLevel = baselight.getBaselightLevel(battleKey, 0, 0);
        assertEq(baselightLevel, 1, "Baselight should start at 1 on first switch in");
    }

    function test_baselightGainsOnePerRound() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Baselight starts at 1 (turn 0 doesn't increment)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Should start at 1");

        // After round 1, should be 2
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0
        );
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 2, "Should be 2 after round 1");

        // After round 2, should be 3 (max)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0
        );
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 3, "Should be 3 (max) after round 2");

        // After round 3, should still be 3 (capped at max)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0
        );
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 3, "Should stay at 3 (max)");
    }

    // ============ Brightback Tests ============

    function test_brightbackHealsWithStack() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory aliceMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon memory bobMon = Mon({
            stats: MonStats({
                hp: 10000,
                stamina: 20,
                speed: 50,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aliceMon;
        aliceTeam[1] = aliceMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = bobMon;
        bobTeam[1] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Alice starts with 1 Baselight stack
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Should start with 1 stack");

        // Bob damages Alice first
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, 0, 0
        );

        // Get Alice's HP before Brightback
        int32 aliceHpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertTrue(aliceHpBefore < 0, "Alice should have taken damage");

        // After round, Baselight is now 2 (gained 1 from round end)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 2, "Should be 2 after round");

        // Alice uses Brightback - should consume 1 stack and heal
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, 0, 0
        );

        // Check Baselight decreased by 1
        // Note: After round ends, it gains 1 back, so net is same (2 - 1 + 1 = 2, but cap is 3)
        uint256 afterBrightback = baselight.getBaselightLevel(battleKey, 0, 0);
        assertEq(afterBrightback, 2, "Baselight should be 2 (consumed 1, gained 1 at round end)");

        // Check Alice healed
        int32 aliceHpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertTrue(aliceHpAfter > aliceHpBefore, "Alice should have healed");
    }

    function test_brightbackNoHealWithoutStack() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0)) // No Baselight ability, so no stacks
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // No Baselight stacks
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 0, "Should have 0 stacks without ability");

        // Bob damages Alice
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, 0, 0
        );

        int32 aliceHpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertTrue(aliceHpBefore < 0, "Alice should have taken damage");

        // Alice uses Brightback - should NOT heal (no stacks)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 aliceHpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertEq(aliceHpAfter, aliceHpBefore, "Alice should not have healed without stacks");
    }

    // ============ Unbounded Strike Tests ============

    function test_unboundedStrikeNormalPower() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory aliceMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon memory bobMon = Mon({
            stats: MonStats({
                hp: 10000,
                stamina: 20,
                speed: 50,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aliceMon;
        aliceTeam[1] = aliceMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = bobMon;
        bobTeam[1] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Alice has 1 stack (not 3), so normal power (80)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Should have 1 stack");

        // Alice uses Unbounded Strike
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 1, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 bobHpDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        assertTrue(bobHpDelta < 0, "Bob should have taken damage");

        // Stacks should NOT be consumed (still 1, but round end adds 1 = 2)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 2, "Stacks should not be consumed at < 3");
    }

    function test_unboundedStrikeEmpoweredPower() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory aliceMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon memory bobMon = Mon({
            stats: MonStats({
                hp: 10000,
                stamina: 20,
                speed: 50,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aliceMon;
        aliceTeam[1] = aliceMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = bobMon;
        bobTeam[1] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Wait for 3 stacks (start at 1, need 2 more rounds)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0);

        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 3, "Should have 3 stacks");

        // Get Bob's HP before
        int32 bobHpBefore = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);

        // Alice uses Unbounded Strike at 3 stacks - empowered (130 power)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 1, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 bobHpAfter = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        int32 damageDealt = bobHpBefore - bobHpAfter;
        assertTrue(damageDealt > 0, "Bob should have taken damage");

        // All stacks consumed (but round end adds 1, so should be 1)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Stacks should be consumed to 0 then gain 1 at round end");
    }

    // ============ Loop Tests ============

    function test_loopAppliesStatBoosts() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // At Baselight 1, Loop should give 15% boost
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Should have 1 stack");

        // Get stats before Loop
        int32 attackBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);

        // Alice uses Loop
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        // Check stats are boosted (15% of 100 = 15)
        int32 attackAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(attackAfter - attackBefore, 15, "Attack should be boosted by 15%");

        // Loop should be marked as active
        assertTrue(loop.isLoopActive(battleKey, 0, 0), "Loop should be active");
    }

    function test_loopFailsIfAlreadyActive() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Alice uses Loop first time
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackAfterFirst = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertTrue(loop.isLoopActive(battleKey, 0, 0), "Loop should be active");

        // Alice uses Loop second time - should fail
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackAfterSecond = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(attackAfterSecond, attackAfterFirst, "Attack should not change when Loop fails");
    }

    function test_loopBoostPercentages() public {
        // Test that Loop gives correct boosts at different Baselight levels
        // Level 1: 15%, Level 2: 30%, Level 3: 40%

        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Wait for 3 stacks
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, 0, 0);

        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 3, "Should have 3 stacks");

        // Get stats before Loop
        int32 attackBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);

        // Alice uses Loop at level 3 - should get 40% boost
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(attackAfter - attackBefore, 40, "Attack should be boosted by 40% at level 3");
    }

    // ============ Renormalize Tests ============

    function test_renormalizeSetsBaselightToThree() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Start at 1 stack
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 1, "Should have 1 stack");

        // Alice uses Renormalize
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 3, NO_OP_MOVE_INDEX, 0, 0
        );

        // Should be at 3 stacks (set to 3, then capped at max even with round end)
        assertEq(baselight.getBaselightLevel(battleKey, 0, 0), 3, "Baselight should be set to 3");
    }

    function test_renormalizeClearsStatBoosts() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Alice uses Loop to get stat boosts
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackBoosted = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertTrue(attackBoosted > 0, "Attack should be boosted");

        // Alice uses Renormalize - should clear stat boosts
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 3, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackAfterRenormalize = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(attackAfterRenormalize, 0, "Attack boost should be cleared");
    }

    function test_renormalizeClearsLoopActive() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Alice uses Loop
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        assertTrue(loop.isLoopActive(battleKey, 0, 0), "Loop should be active");

        // Alice uses Renormalize
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 3, NO_OP_MOVE_INDEX, 0, 0
        );

        assertFalse(loop.isLoopActive(battleKey, 0, 0), "Loop should no longer be active");

        // Alice can use Loop again
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, 0, 0
        );

        int32 attackBoosted = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertTrue(attackBoosted > 0, "Attack should be boosted again after Renormalize");
    }

    function test_renormalizeHasLowerPriority() public {
        // Renormalize should have -1 priority (DEFAULT_PRIORITY - 1 = 2)
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = brightback;
        moves[1] = unboundedStrike;
        moves[2] = loop;
        moves[3] = renormalize;

        Mon memory fastMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 100,
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon memory slowMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 20,
                speed: 10, // Much slower
                attack: 100,
                defense: 100,
                specialAttack: 100,
                specialDefense: 100,
                type1: Type.Yin,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(baselight))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = fastMon;
        aliceTeam[1] = fastMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = slowMon;
        bobTeam[1] = slowMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, uint240(0), uint240(0)
        );

        // Check priority
        uint32 renomalPriority = renormalize.priority(battleKey, 0);
        assertEq(renomalPriority, DEFAULT_PRIORITY - 1, "Renormalize should have -1 priority");
    }
}
