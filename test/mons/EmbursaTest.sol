// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Structs.sol";
import {Test} from "forge-std/Test.sol";

import {Engine} from "../../src/Engine.sol";
import {MonStateIndexName, MoveClass, Type} from "../../src/Enums.sol";
import {FastCommitManager} from "../../src/FastCommitManager.sol";

import {FastValidator} from "../../src/FastValidator.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IRuleset} from "../../src/IRuleset.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {ITeamRegistry} from "../../src/teams/ITeamRegistry.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

import {BattleHelper} from "../abstract/BattleHelper.sol";

import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";

import {SplitThePot} from "../../src/mons/embursa/SplitThePot.sol";
import {Q5} from "../../src/mons/embursa/Q5.sol";
import {HeatBeacon} from "../../src/mons/embursa/HeatBeacon.sol";
import {SetAblaze} from "../../src/mons/embursa/SetAblaze.sol";
import {DummyStatus} from "../mocks/DummyStatus.sol";
import {HoneyBribe} from "../../src/mons/embursa/HoneyBribe.sol";
import {StatBoosts} from "../../src/effects/StatBoosts.sol";

contract EmbursaTest is Test, BattleHelper {
    Engine engine;
    FastCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    FastValidator validator;
    SplitThePot splitThePot;
    StandardAttackFactory attackFactory;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );
        commitManager = new FastCommitManager(IEngine(address(engine)));
        engine.setMoveManager(address(commitManager));
        splitThePot = new SplitThePot(IEngine(address(engine)));
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
    }

    function test_splitThePot_healing() public {
        // Create a team with two mons that have SplitThePot ability
        int32 hpScale = 100;

        // Create an attack that deals exactly HEAL_DENOM damage
        IMoveSet standardAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: uint32(hpScale) * 2,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "DamageAttack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = standardAttack;

        // Create two mons with SplitThePot ability and HP = hpScale * HEAL_DENOM
        Mon memory embursa = Mon({
            stats: MonStats({
                hp: uint32(splitThePot.HEAL_DENOM() * hpScale),
                stamina: 5,
                speed: 10,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(splitThePot))
        });

        // Create a regular mon for the opponent
        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: uint32(splitThePot.HEAL_DENOM() * hpScale),
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        // Create teams
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = embursa;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        // Start battle
        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Test 1: Both players NO_OP, which should not trigger healing for p0 as all mons are at full HP
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify no healing occurred
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp), 0, "Mon 0 should not be healed");
        assertEq(engine.getMonStateForBattle(battleKey, 0, 1, MonStateIndexName.Hp), 0, "Mon 1 should not be healed");

        // First, Bob deals damage, and Alice does a No-Op
        // Alice moves first (higher speed), so this shouldn't heal her because it's before damage is done
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Verify damage occurred
        assertEq(
            engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp),
            -2 * hpScale,
            "Mon 0 should have taken damage"
        );

        // Next, both players do a No-Op, which should trigger healing for p0
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify healing occurred
        // Mon 0 should be healed by HEAL_DENOM/HEAL_DENOM = 1/16 of max HP
        assertEq(
            engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp),
            -1 * hpScale,
            "Mon 0 should be healed by 1/DENOM of max HP"
        );

        // Now, Alice should switch to mon index 1, and Bob should choose the damage move
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(1), "");

        // Verify damage occurred
        assertEq(
            engine.getMonStateForBattle(battleKey, 0, 1, MonStateIndexName.Hp),
            -2 * hpScale,
            "Mon 1 should have taken damage"
        );

        // Next, both players do a No-Op, which should NOT trigger healing for p0 as mon 1 does not have SplitThePot
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify no healing occurred
        assertEq(engine.getMonStateForBattle(battleKey, 0, 1, MonStateIndexName.Hp), -2 * hpScale, "Mon 1 should not be healed");

        // Next, Alice switches back to mon index 0, and Bob chooses to No-Op
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), "");

        // Verify no healing occurred
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp), -1 * hpScale, "Mon 0 should not be healed");

        // Next, both players do a No-Op, which should trigger healing for p0 (both mons)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify healing occurred for both mons
        assertEq(
            engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp),
            0,
            "Mon 0 should be healed by 1/DENOM of max HP"
        );
        assertEq(
            engine.getMonStateForBattle(battleKey, 0, 1, MonStateIndexName.Hp),
            -1 * hpScale,
            "Mon 1 should be healed by 1/DENOM of max HP"
        );
    }

    function test_q5() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = new Q5(engine, typeCalc);

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        IValidator validatorToUse = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        // Start battle
        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Q5, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify no damage occurred
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp), 0, "No damage should have occurred");

        // Wait 4 turns
        for (uint256 i = 0; i < 4; i++) {
            _commitRevealExecuteForAliceAndBob(
                engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), abi.encode(0)
            );
        }
        // Verify no damage occurred
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp), 0, "No damage should have occurred");

        // Set rng to be 2 (magic number that cancels out the damage calc volatility stuff)
        mockOracle.setRNG(2);

        // Alice and Bob both do nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify damage occurred
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp), -150, "Damage should have occurred");
    }

    function test_heatBeacon() public {
        DummyStatus dummyStatus = new DummyStatus();
        HeatBeacon heatBeacon = new HeatBeacon(IEngine(address(engine)), IEffect(address(dummyStatus)));
        Q5 q5 = new Q5(engine, typeCalc);
        SetAblaze setAblaze = new SetAblaze(engine, typeCalc, IEffect(address(dummyStatus)));
        StatBoosts statBoosts = new StatBoosts(engine);
        HoneyBribe honeyBribe = new HoneyBribe(engine, statBoosts);

        IMoveSet koMove = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 200,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "KO Move",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory aliceMoves = new IMoveSet[](5);
        aliceMoves[0] = heatBeacon;
        aliceMoves[1] = q5;
        aliceMoves[2] = setAblaze;
        aliceMoves[3] = honeyBribe;
        aliceMoves[4] = koMove;

        Mon memory aliceMon = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 10,
                speed: 1,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: aliceMoves,
            ability: IAbility(address(0))
        });

        // 5. Create Bob's mon with higher speed
        IMoveSet[] memory bobMoves = new IMoveSet[](5);
        bobMoves[0] = heatBeacon;
        bobMoves[1] = q5;
        bobMoves[2] = setAblaze;
        bobMoves[3] = honeyBribe;
        bobMoves[4] = koMove;

        Mon memory bobMon = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 10,
                speed: 2, // Higher speed than Alice
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: bobMoves,
            ability: IAbility(address(0))
        });
        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;
        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);
        IValidator validatorToUse = new FastValidator(
            IEngine(address(engine)),
            FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 5, TIMEOUT_DURATION: 10})
        );

        // Set Ablaze test
        // Start battle
        // Alice uses Heat Beacon, Bob does nothing
        // Verify dummy status was applied to Bob's mon
        // Verify Alice's priority boost
        // Alice uses Set Ablaze, Bob uses KO move
        // Verify Alice's priority boost is cleared
        // Verify Alice's mon is KO'ed but Bob has taken damage
        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry);
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );
        (IEffect[] memory effects, ) = engine.getEffects(battleKey, 1, 0);
        assertEq(effects.length, 1, "Bob's mon should have 1 effect (Dummy status)");
        assertEq(address(effects[0]), address(dummyStatus), "Bob's mon should have Dummy status");
        assertEq(heatBeacon.priority(battleKey, 0), DEFAULT_PRIORITY + 1, "Alice should have priority boost");
        mockOracle.setRNG(2); // Magic number to cancel out volatility
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 2, 4, "", ""
        );
        assertEq(heatBeacon.priority(battleKey, 0), DEFAULT_PRIORITY, "Alice's priority boost should be cleared");
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice's mon should be KOed");
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp), -1 * int32(setAblaze.basePower(battleKey)), "Bob's mon should take damage");

        // Heat Beacon test
        // Start a new battle
        // Alice uses Heat Beacon, Bob does nothing
        // Alice uses Heat Beacon again, Bob uses KO Move
        // Verify Alice's mon is KO'ed but Bob's mon now has 2x Dummy status
        battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry);
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, 4, "", ""
        );
        (effects,) = engine.getEffects(battleKey, 1, 0);
        assertEq(effects.length, 2, "Bob's mon should have 2x Dummy status");

        // Q5 test
        // Start a new battle
        // Alice uses Heat Beacon, Bob does nothing
        // Alice uses Q5, Bob uses KO move
        // Verify Q5 was applied to global effects, verify Alice is KOed
        battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry);
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 1, 4, "", ""
        );
        (effects,) = engine.getEffects(battleKey, 2, 0);
        assertEq(address(effects[0]), address(q5), "Q5 should be applied to global effects");
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice's mon should be KOed");

        // Honey Bribe test
        // Start a new battle
        // Alice uses Heat Beacon, Bob does nothing
        // Alice uses Honey Bribe, Bob uses KO move
        // Verify Honey Bribe applied stat boost to Bob's mon, verify Alice is KOed
        battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry);
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 3, 4, "", ""
        );
        (effects,) = engine.getEffects(battleKey, 1, 0);
        assertEq(address(effects[1]), address(statBoosts), "StatBoosts should be applied to Bob's mon");
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice's mon should be KOed");
    }

}
