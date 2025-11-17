// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import "../../src/Constants.sol";
import "../../src/Structs.sol";

import {DefaultCommitManager} from "../../src/DefaultCommitManager.sol";
import {DefaultValidator} from "../../src/DefaultValidator.sol";
import {Engine} from "../../src/Engine.sol";
import {MonStateIndexName, MoveClass, Type} from "../../src/Enums.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IEngineHook} from "../../src/IEngineHook.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IRuleset} from "../../src/IRuleset.sol";
import {DefaultRuleset} from "../../src/DefaultRuleset.sol";
import {SleepStatus} from "../../src/effects/status/SleepStatus.sol";
import {StaminaRegen} from "../../src/effects/StaminaRegen.sol";
import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";
import {BattleHelper} from "../abstract/BattleHelper.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

// Xmon moves and abilities
import {ContagiousSlumber} from "../../src/mons/xmon/ContagiousSlumber.sol";
import {VitalSiphon} from "../../src/mons/xmon/VitalSiphon.sol";
import {Somniphobia} from "../../src/mons/xmon/Somniphobia.sol";
import {Dreamcatcher} from "../../src/mons/xmon/Dreamcatcher.sol";

/**
    - Contagious Slumber adds Sleep effect to both mons [x]
    - Vital Siphon drains stamina only when opponent has at least 1 stamina [x]
    - Somniphobia correctly damages both mons if they choose to NO_OP [x]
    - Dreamcatcher heals on stamina gain [x]
 */

contract XmonTest is Test, BattleHelper {
    Engine engine;
    DefaultCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    DefaultMatchmaker matchmaker;
    StandardAttackFactory attackFactory;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        commitManager = new DefaultCommitManager(IEngine(address(engine)));
        matchmaker = new DefaultMatchmaker(engine);
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
    }

    function test_contagiousSlumberAppliesSleepToBothMons() public {
        SleepStatus sleepStatus = new SleepStatus(IEngine(address(engine)));
        ContagiousSlumber contagiousSlumber = new ContagiousSlumber(IEngine(address(engine)), IEffect(address(sleepStatus)));

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = contagiousSlumber;

        Mon memory mon = _createMon();
        mon.moves = moves;
        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Contagious Slumber, Bob does nothing
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify that both Alice and Bob have Sleep status
        EffectInstance[] memory aliceEffects = engine.getEffects(battleKey, 0, 0);
        EffectInstance[] memory bobEffects = engine.getEffects(battleKey, 1, 0);

        bool aliceHasSleep = false;
        bool bobHasSleep = false;

        for (uint256 i = 0; i < aliceEffects.length; i++) {
            if (address(aliceEffects[i].effect) == address(sleepStatus)) {
                aliceHasSleep = true;
                break;
            }
        }

        for (uint256 i = 0; i < bobEffects.length; i++) {
            if (address(bobEffects[i].effect) == address(sleepStatus)) {
                bobHasSleep = true;
                break;
            }
        }

        assertTrue(aliceHasSleep, "Alice should have Sleep status");
        assertTrue(bobHasSleep, "Bob should have Sleep status");
    }

    function test_vitalSiphonDrainsStaminaOnlyWhenOpponentHasStamina() public {
        VitalSiphon vitalSiphon = new VitalSiphon(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));

        // Create a stamina-draining attack to reduce Bob's stamina to 0
        StandardAttack staminaDrain = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Cosmic,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Special,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Stamina Drain",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = vitalSiphon;
        moves[1] = staminaDrain;

        Mon memory mon = _createMon();
        mon.moves = moves;
        mon.stats.stamina = 10; // Enough stamina for multiple moves
        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Set RNG to guarantee stamina steal (>= 50)
        mockOracle.setRNG(50);

        // Alice uses Vital Siphon, Bob does nothing
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify that Bob's stamina was drained by 1 and Alice gained 1
        int32 bobStaminaDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Stamina);
        int32 aliceStaminaDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice spent 2 stamina for the move, gained 1 back = -1
        // Bob gained 1 from rest, lost 1 from drain = 0
        assertEq(aliceStaminaDelta, -1, "Alice should have -1 stamina delta (spent 2, gained 1)");
        assertEq(bobStaminaDelta, 0, "Bob should have 0 stamina delta (gained 1 from rest, lost 1 from drain)");

        // Alice rests, Bob uses stamina drain to spend his last stamina
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 1, "", "");

        // Alice gained 1 from rest: -1 + 1 = 0
        // Bob spent 1 for the move: 0 - 1 = -1
        bobStaminaDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Stamina);
        aliceStaminaDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);
        assertEq(bobStaminaDelta, -1, "Bob should have -1 stamina delta");
        assertEq(aliceStaminaDelta, 0, "Alice should have 0 stamina delta");

        // Bob should now have 0 total stamina (base 1 + delta -1 = 0)
        // Set RNG to guarantee stamina steal attempt (>= 50)
        mockOracle.setRNG(50);

        // Alice uses Vital Siphon again, Bob does nothing
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify that Bob's stamina was NOT drained (he has 0 stamina) and Alice did NOT gain stamina
        bobStaminaDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Stamina);
        aliceStaminaDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice spent 2 stamina for the move, gained nothing = 0 - 2 = -2 total
        // Bob gained 1 from rest = -1 + 1 = 0 total (still has 0 total stamina, so no steal)
        assertEq(aliceStaminaDelta, -2, "Alice should have -2 stamina delta (no steal occurred)");
        assertEq(bobStaminaDelta, 0, "Bob should have 0 stamina delta (gained 1 from rest, no drain)");
    }

    function test_somniphobiaDamagesMonsWhoRest() public {
        Somniphobia somniphobia = new Somniphobia(IEngine(address(engine)));

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = somniphobia;

        Mon memory mon = _createMon();
        mon.moves = moves;
        // Set HP to be a multiple of DAMAGE_DENOM (16) for easy math
        mon.stats.hp = uint32(somniphobia.DAMAGE_DENOM()) * 10; // 160 HP
        Mon[] memory team = new Mon[](1);
        team[0] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, address(commitManager));

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Somniphobia, Bob uses Somniphobia too
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 0, "", "");

        // Verify that the global effect is applied
        EffectInstance[] memory globalEffects = engine.getEffects(battleKey, 2, 2);
        bool hasSomniphobia = false;
        for (uint256 i = 0; i < globalEffects.length; i++) {
            if (address(globalEffects[i].effect) == address(somniphobia)) {
                hasSomniphobia = true;
                break;
            }
        }
        assertTrue(hasSomniphobia, "Somniphobia effect should be applied globally");

        // Both players rest (NO_OP)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify that both mons took 1/16 of max HP as damage (160 / 16 = 10)
        int32 aliceHpDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 bobHpDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);

        int32 expectedDamage = -10; // 160 / 16 = 10
        assertEq(aliceHpDelta, expectedDamage, "Alice should take 1/16 max HP damage for resting");
        assertEq(bobHpDelta, expectedDamage, "Bob should take 1/16 max HP damage for resting");

        // Alice rests, Bob does nothing (but doesn't rest)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Verify that only Alice took additional damage
        aliceHpDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        bobHpDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);

        assertEq(aliceHpDelta, expectedDamage * 2, "Alice should take damage again for resting");
        assertEq(bobHpDelta, expectedDamage, "Bob should not take additional damage (didn't rest)");
    }

    function test_dreamcatcherHealsOnStaminaGain() public {
        Dreamcatcher dreamcatcher = new Dreamcatcher(IEngine(address(engine)));
        StaminaRegen staminaRegen = new StaminaRegen(IEngine(address(engine)));

        uint32 BASE_HP = 10;
        uint32 maxHp = uint32(dreamcatcher.HEAL_DENOM()) * BASE_HP; // 160 HP

        // Create an attack that deals damage
        StandardAttack attack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 3 * BASE_HP,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Cosmic,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Attack",
                EFFECT: IEffect(address(0))
            })
        );

        // Create a move that costs 3 stamina and does nothing
        StandardAttack staminaBurn = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 3,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Cosmic,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Stamina Burn",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = attack;
        moves[1] = staminaBurn;

        Mon memory fastMon = _createMon();
        fastMon.moves = moves;
        fastMon.ability = dreamcatcher;
        fastMon.stats.hp = maxHp;
        fastMon.stats.stamina = 10;
        fastMon.stats.speed = 2;

        Mon memory slowMon = _createMon();
        slowMon.moves = moves;
        slowMon.ability = dreamcatcher;
        slowMon.stats.hp = maxHp;
        slowMon.stats.stamina = 10;
        slowMon.stats.speed = 1;

        Mon[] memory team = new Mon[](2);
        team[0] = fastMon;
        team[1] = slowMon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: team.length, MOVES_PER_MON: moves.length, TIMEOUT_DURATION: 10})
        );

        // Create ruleset with StaminaRegen
        IEffect[] memory effects = new IEffect[](1);
        effects[0] = staminaRegen;
        DefaultRuleset ruleset = new DefaultRuleset(IEngine(address(engine)), effects);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, new IEngineHook[](0), IRuleset(address(ruleset)), address(commitManager));

        // Alice sends in fast mon, Bob sends in slow mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(1)
        );

        // Verify that Alice has the Dreamcatcher effect
        EffectInstance[] memory aliceEffects = engine.getEffects(battleKey, 0, 0);
        bool hasDreamcatcher = false;
        for (uint256 i = 0; i < aliceEffects.length; i++) {
            if (address(aliceEffects[i].effect) == address(dreamcatcher)) {
                hasDreamcatcher = true;
                break;
            }
        }
        assertTrue(hasDreamcatcher, "Alice should have Dreamcatcher effect");

        // Turn 1: Alice uses stamina burn (loses 3 stamina), Bob attacks Alice
        // At end of turn: Alice regains 1 stamina (from StaminaRegen), heals by 10 (from Dreamcatcher)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 1, 0, "", "");

        int32 aliceHpAfterTurn1 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertEq(aliceHpAfterTurn1, -20);

        // Turn 2: Both players rest (NO_OP)
        // Alice heals from resting, then heals again at end of turn from stamina regen
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify Alice is back to full HP
        int32 aliceHpAfterTurn2 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertEq(aliceHpAfterTurn2, 0, "Alice should be back to full HP");
    }
}
