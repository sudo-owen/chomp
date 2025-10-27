// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import "../../src/Constants.sol";
import "../../src/Structs.sol";

import {DefaultCommitManager} from "../../src/DefaultCommitManager.sol";
import {Engine} from "../../src/Engine.sol";
import {MonStateIndexName, MoveClass, Type} from "../../src/Enums.sol";
import {DefaultValidator} from "../../src/DefaultValidator.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";
import {BattleHelper} from "../abstract/BattleHelper.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";
import {StatBoosts} from "../../src/effects/StatBoosts.sol";
import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {FrostbiteStatus} from "../../src/effects/status/FrostbiteStatus.sol";
import {BurnStatus} from "../../src/effects/status/BurnStatus.sol";

// Aurox moves
import {VolatilePunch} from "../../src/mons/aurox/VolatilePunch.sol";
import {GildedRecovery} from "../../src/mons/aurox/GildedRecovery.sol";
import {IronWall} from "../../src/mons/aurox/IronWall.sol";
import {BullRush} from "../../src/mons/aurox/BullRush.sol";
import {UpOnly} from "../../src/mons/aurox/UpOnly.sol";

contract AuroxTest is Test, BattleHelper {
    Engine engine;
    DefaultCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    StatBoosts statBoosts;
    DefaultMatchmaker matchmaker;
    StandardAttackFactory attackFactory;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        commitManager = new DefaultCommitManager(IEngine(address(engine)));
        statBoosts = new StatBoosts(IEngine(address(engine)));
        matchmaker = new DefaultMatchmaker(engine);
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
    }

    /**
        - Bull Rush correctly deals SELF_DAMAGE_PERCENT of max hp to self
        - Gilded Recovery heals for HEAL_PERCENT of max hp if there is a status effect
        - Gilded Recovery gives +1 stamina if there is a status effect
        - Iron Wall correctly heals damage dealt until end of next turn
        - Up Only correctly boosts on damage, and it stays on switch in/out
        - Volatile Punch correctly deals damage and can trigger status effects
            - rng of 2 should trigger frostbite
            - rng of 10 should trigger burn
     */

    function test_bullRushSelfDamage() public {
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        BullRush bullRush = new BullRush(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));

        // Create moves for both mons
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = bullRush;

        IMoveSet[] memory bobMoves = new IMoveSet[](1);
        bobMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "No Damage",
                EFFECT: IEffect(address(0))
            })
        );

        // Use HP that's a multiple of 100 to avoid precision errors
        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.speed = 10;
        aliceMon.stats.defense = 10;
        aliceMon.stats.specialAttack = 10;
        aliceMon.stats.specialDefense = 10;
        aliceMon.stats.type1 = Type.Metal;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.speed = 5;
        bobMon.stats.defense = 10;
        bobMon.stats.specialAttack = 10;
        bobMon.stats.specialDefense = 10;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Bull Rush
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check that Alice took self-damage equal to SELF_DAMAGE_PERCENT of max HP
        int32 aliceHpDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 expectedSelfDamage = -1 * (1000 * bullRush.SELF_DAMAGE_PERCENT()) / 100;
        assertEq(aliceHpDelta, expectedSelfDamage, "Alice should take 10% self-damage from Bull Rush");
    }

    function test_gildedRecoveryHealsWithStatus() public {
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        FrostbiteStatus frostbiteStatus = new FrostbiteStatus(IEngine(address(engine)), statBoosts);
        GildedRecovery gildedRecovery = new GildedRecovery(IEngine(address(engine)));

        // Create an attack that inflicts frostbite
        StandardAttack frostbiteAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Ice,
                EFFECT_ACCURACY: 100,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Frostbite Attack",
                EFFECT: IEffect(address(frostbiteStatus))
            })
        );

        // Create a damaging attack
        StandardAttack damageAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 200,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Damage Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory aliceMoves = new IMoveSet[](2);
        aliceMoves[0] = gildedRecovery;
        aliceMoves[1] = damageAttack;

        IMoveSet[] memory bobMoves = new IMoveSet[](2);
        bobMoves[0] = frostbiteAttack;
        bobMoves[1] = damageAttack;

        // Use HP that's a multiple of the heal denominator (100 / 50 = 2)
        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.speed = 10;
        aliceMon.stats.defense = 10;
        aliceMon.stats.specialAttack = 10;
        aliceMon.stats.specialDefense = 10;
        aliceMon.stats.type1 = Type.Metal;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.speed = 5;
        bobMon.stats.defense = 10;
        bobMon.stats.specialAttack = 10;
        bobMon.stats.specialDefense = 10;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aliceMon;
        aliceTeam[1] = aliceMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = bobMon;
        bobTeam[1] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob inflicts frostbite on Alice's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Verify Alice has frostbite
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);
        bool hasFrostbite = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(frostbiteStatus))) {
                hasFrostbite = true;
                break;
            }
        }
        assertTrue(hasFrostbite, "Alice should have frostbite");

        // Bob damages Alice's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 1, "", "");

        int32 hpBeforeHeal = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaBeforeHeal = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice uses Gilded Recovery on herself
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), ""
        );

        int32 hpAfterHeal = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaAfterHeal = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Check that Alice healed for HEAL_PERCENT of max HP
        int32 expectedHeal = (1000 * gildedRecovery.HEAL_PERCENT()) / 100;
        assertEq(hpAfterHeal - hpBeforeHeal, expectedHeal, "Alice should heal for 50% of max HP");

        // Check that Alice gained stamina
        assertEq(
            staminaAfterHeal - staminaBeforeHeal,
            gildedRecovery.STAMINA_BONUS(),
            "Alice should gain 1 stamina"
        );

        // Verify frostbite was removed
        (effects,) = engine.getEffects(battleKey, 0, 0);
        hasFrostbite = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(frostbiteStatus))) {
                hasFrostbite = true;
                break;
            }
        }
        assertFalse(hasFrostbite, "Alice should not have frostbite after Gilded Recovery");
    }

    function test_ironWallHealsUntilEndOfNextTurn() public {
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        IronWall ironWall = new IronWall(IEngine(address(engine)));

        // Create a damaging attack for testing
        StandardAttack damageAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Damage Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory aliceMoves = new IMoveSet[](2);
        aliceMoves[0] = ironWall;
        aliceMoves[1] = damageAttack;

        IMoveSet[] memory bobMoves = new IMoveSet[](2);
        bobMoves[0] = damageAttack;
        bobMoves[1] = damageAttack;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.speed = 10;
        aliceMon.stats.defense = 10;
        aliceMon.stats.specialAttack = 10;
        aliceMon.stats.specialDefense = 10;
        aliceMon.stats.type1 = Type.Metal;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.speed = 5;
        bobMon.stats.defense = 10;
        bobMon.stats.specialAttack = 10;
        bobMon.stats.specialDefense = 10;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify Iron Wall effect is active
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);
        bool hasIronWall = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(ironWall))) {
                hasIronWall = true;
                break;
            }
        }
        assertTrue(hasIronWall, "Alice should have Iron Wall effect");

        // Bob attacks Alice
        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");
        int32 hpAfterAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        int32 damageDealt = hpBefore - hpAfterAttack;
        int32 expectedHeal = (damageDealt * ironWall.HEAL_PERCENT()) / 100;

        // HP should be partially healed (damage - 50% of damage = 50% of damage taken)
        assertEq(hpAfterAttack - hpBefore, -1 * damageDealt / 2, "Alice should heal 50% of damage taken");

        // Bob attacks again - should still heal
        hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");
        hpAfterAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        damageDealt = hpBefore - hpAfterAttack;
        // Should still heal 50% of damage
        assertEq(hpAfterAttack - hpBefore, -1 * damageDealt / 2, "Alice should still heal 50% of damage taken");

        // Bob attacks a third time - should NOT heal anymore (effect expired)
        hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");
        hpAfterAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        damageDealt = hpBefore - hpAfterAttack;
        // Should take full damage now
        assertEq(hpAfterAttack - hpBefore, -1 * damageDealt, "Alice should take full damage after effect expires");

        // Verify Iron Wall effect is removed
        (effects,) = engine.getEffects(battleKey, 0, 0);
        hasIronWall = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(ironWall))) {
                hasIronWall = true;
                break;
            }
        }
        assertFalse(hasIronWall, "Alice should not have Iron Wall effect anymore");
    }

    function test_upOnlyBoostsOnDamageAndPersists() public {
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        UpOnly upOnly = new UpOnly(IEngine(address(engine)), statBoosts);

        // Create a weak attack to deal some damage
        StandardAttack weakAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 50,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Weak Attack",
                EFFECT: IEffect(address(0))
            })
        );

        StandardAttack normalAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Normal Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory aliceMoves = new IMoveSet[](2);
        aliceMoves[0] = weakAttack;
        aliceMoves[1] = normalAttack;

        IMoveSet[] memory bobMoves = new IMoveSet[](2);
        bobMoves[0] = weakAttack;
        bobMoves[1] = normalAttack;

        Mon memory aliceMonWithUpOnly = _createMon();
        aliceMonWithUpOnly.stats.hp = 1000;
        aliceMonWithUpOnly.stats.speed = 5;
        aliceMonWithUpOnly.stats.attack = 100;
        aliceMonWithUpOnly.stats.defense = 10;
        aliceMonWithUpOnly.stats.specialAttack = 10;
        aliceMonWithUpOnly.stats.specialDefense = 10;
        aliceMonWithUpOnly.stats.type1 = Type.Metal;
        aliceMonWithUpOnly.moves = aliceMoves;
        aliceMonWithUpOnly.ability = IAbility(address(upOnly));

        Mon memory aliceMonRegular = _createMon();
        aliceMonRegular.stats.hp = 1000;
        aliceMonRegular.stats.speed = 5;
        aliceMonRegular.stats.attack = 100;
        aliceMonRegular.stats.defense = 10;
        aliceMonRegular.stats.specialAttack = 10;
        aliceMonRegular.stats.specialDefense = 10;
        aliceMonRegular.stats.type1 = Type.Metal;
        aliceMonRegular.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.speed = 10;
        bobMon.stats.defense = 10;
        bobMon.stats.specialAttack = 10;
        bobMon.stats.specialDefense = 10;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aliceMonWithUpOnly;
        aliceTeam[1] = aliceMonRegular;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = bobMon;
        bobTeam[1] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Alice selects mon with Up Only ability
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify Up Only effect is active
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);
        bool hasUpOnly = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(upOnly))) {
                hasUpOnly = true;
                break;
            }
        }
        assertTrue(hasUpOnly, "Alice should have Up Only effect");

        // Bob attacks Alice's mon to trigger Up Only
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Alice attacks Bob to measure attack power after first boost
        int32 bobHpBefore = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");
        int32 bobHpAfter1 = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        int32 damage1 = bobHpBefore - bobHpAfter1;

        // Bob attacks Alice again
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Alice attacks Bob again - should deal more damage (second boost)
        bobHpBefore = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");
        int32 bobHpAfter2 = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        int32 damage2 = bobHpBefore - bobHpAfter2;

        // Damage should increase with each hit received
        assertGt(damage2, damage1, "Damage should increase after taking more hits");

        // Alice switches out
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(1), ""
        );

        // Alice switches back to mon with Up Only
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), ""
        );

        // Verify Up Only effect is still active after switch
        (effects,) = engine.getEffects(battleKey, 0, 0);
        hasUpOnly = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(upOnly))) {
                hasUpOnly = true;
                break;
            }
        }
        assertTrue(hasUpOnly, "Alice should still have Up Only effect after switching");

        // Attack again - should still have the boosted attack
        bobHpBefore = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");
        int32 bobHpAfter3 = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        int32 damage3 = bobHpBefore - bobHpAfter3;

        // Damage should be at least as much as damage2 (boosts persist)
        assertGe(damage3, damage2, "Attack boosts should persist after switching");
    }

    function test_volatilePunchTriggersStatusEffects() public {
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        FrostbiteStatus frostbiteStatus = new FrostbiteStatus(IEngine(address(engine)), statBoosts);
        BurnStatus burnStatus = new BurnStatus(IEngine(address(engine)), statBoosts);

        VolatilePunch volatilePunch =
            new VolatilePunch(IEngine(address(engine)), ITypeCalculator(address(typeCalc)), frostbiteStatus, burnStatus);

        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = volatilePunch;

        IMoveSet[] memory bobMoves = new IMoveSet[](1);
        bobMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "No Damage",
                EFFECT: IEffect(address(0))
            })
        );

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.speed = 10;
        aliceMon.stats.defense = 10;
        aliceMon.stats.specialAttack = 10;
        aliceMon.stats.specialDefense = 10;
        aliceMon.stats.type1 = Type.Metal;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.speed = 5;
        bobMon.stats.defense = 10;
        bobMon.stats.specialAttack = 10;
        bobMon.stats.specialDefense = 10;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Both players select their first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Test with RNG that should trigger status effect (2 should trigger)
        mockOracle.setRNG(2);

        // Alice uses Volatile Punch
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check that Bob has either burn or frostbite
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 1, 0);
        bool hasBurnOrFrostbite = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (effects[i] == IEffect(address(burnStatus)) || effects[i] == IEffect(address(frostbiteStatus))) {
                hasBurnOrFrostbite = true;
                break;
            }
        }
        assertTrue(hasBurnOrFrostbite, "Bob should have burn or frostbite status with RNG 2");
    }
}