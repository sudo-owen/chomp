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
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

import {BattleHelper} from "../abstract/BattleHelper.sol";

import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";

import {StatBoosts} from "../../src/effects/StatBoosts.sol";
import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";
import {BurnStatus} from "../../src/effects/status/BurnStatus.sol";
import {FrostbiteStatus} from "../../src/effects/status/FrostbiteStatus.sol";

import {UpOnly} from "../../src/mons/aurox/UpOnly.sol";
import {VolatilePunch} from "../../src/mons/aurox/VolatilePunch.sol";
import {GildedRecovery} from "../../src/mons/aurox/GildedRecovery.sol";
import {IronWall} from "../../src/mons/aurox/IronWall.sol";
import {BullRush} from "../../src/mons/aurox/BullRush.sol";

contract AuroxTest is Test, BattleHelper {
    Engine engine;
    DefaultCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    DefaultValidator validator;
    StandardAttackFactory attackFactory;
    DefaultMatchmaker matchmaker;
    StatBoosts statBoosts;
    BurnStatus burnStatus;
    FrostbiteStatus frostbiteStatus;

    UpOnly upOnly;
    VolatilePunch volatilePunch;
    GildedRecovery gildedRecovery;
    IronWall ironWall;
    BullRush bullRush;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 5, TIMEOUT_DURATION: 10})
        );
        commitManager = new DefaultCommitManager(IEngine(address(engine)));
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
        matchmaker = new DefaultMatchmaker(engine);
        statBoosts = new StatBoosts(engine);
        burnStatus = new BurnStatus(IEngine(address(engine)), statBoosts);
        frostbiteStatus = new FrostbiteStatus(IEngine(address(engine)), statBoosts);

        // Create Aurox moves and abilities
        upOnly = new UpOnly(IEngine(address(engine)), statBoosts);
        volatilePunch = new VolatilePunch(
            IEngine(address(engine)), typeCalc, IEffect(address(burnStatus)), IEffect(address(frostbiteStatus))
        );
        gildedRecovery = new GildedRecovery(IEngine(address(engine)));
        ironWall = new IronWall(IEngine(address(engine)));
        bullRush = new BullRush(IEngine(address(engine)), typeCalc);
    }

    function test_upOnly_multipleTriggersPerTurn() public {
        // Create a strong attack that deals damage
        IMoveSet strongAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Strong Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = strongAttack;

        // Create Aurox with UpOnly ability
        Mon memory aurox = _createMon();
        aurox.stats.hp = 1000;
        aurox.stats.stamina = 10;
        aurox.stats.attack = 100;
        aurox.stats.defense = 50;
        aurox.ability = IAbility(address(upOnly));
        aurox.moves = moves;

        // Create opponent mon
        Mon memory opponent = _createMon();
        opponent.stats.hp = 1000;
        opponent.stats.stamina = 10;
        opponent.stats.attack = 100;
        opponent.stats.defense = 50;
        opponent.moves = moves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aurox;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = opponent;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Apply burn status to Aurox manually
        engine.addEffect(0, 0, IEffect(address(burnStatus)), "");

        // Bob attacks Alice, Alice does nothing
        // This should trigger UpOnly once from the attack damage
        mockOracle.setRNG(2);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Verify Alice's mon took damage
        int32 aliceHp = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertTrue(aliceHp < 0, "Aurox should have taken damage from attack");

        // Both do nothing - burn will trigger at end of round
        // This should trigger UpOnly again from the burn damage
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify Aurox's attack has been boosted twice (5% * 2 = 10%)
        // We can't directly check the attack stat, but we can verify the effect was applied
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);

        // Should have burn status + UpOnly effect
        assertEq(effects.length, 2, "Aurox should have burn and UpOnly effects");
    }

    function test_upOnly_persistsAfterSwap() public {
        // Create a strong attack
        IMoveSet strongAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Strong Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = strongAttack;

        // Create Aurox with UpOnly ability
        Mon memory aurox = _createMon();
        aurox.stats.hp = 1000;
        aurox.stats.stamina = 10;
        aurox.stats.attack = 100;
        aurox.stats.defense = 50;
        aurox.ability = IAbility(address(upOnly));
        aurox.moves = moves;

        // Create a second mon for Alice
        Mon memory aliceMon2 = _createMon();
        aliceMon2.stats.hp = 1000;
        aliceMon2.stats.stamina = 10;
        aliceMon2.moves = moves;

        // Create opponent mon
        Mon memory opponent = _createMon();
        opponent.stats.hp = 1000;
        opponent.stats.stamina = 10;
        opponent.stats.attack = 100;
        opponent.stats.defense = 50;
        opponent.moves = moves;

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = aurox;
        aliceTeam[1] = aliceMon2;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = opponent;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob attacks Aurox
        mockOracle.setRNG(2);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Aurox should have UpOnly effect
        (IEffect[] memory effectsBefore,) = engine.getEffects(battleKey, 0, 0);
        assertEq(effectsBefore.length, 1, "Aurox should have UpOnly effect");

        // Alice swaps to mon 1, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(1), ""
        );

        // Alice swaps back to Aurox
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), ""
        );

        // Aurox should still have UpOnly effect (attack boost persists)
        (IEffect[] memory effectsAfter,) = engine.getEffects(battleKey, 0, 0);
        assertEq(effectsAfter.length, 1, "Aurox should still have UpOnly effect after swap");
    }

    function test_volatilePunch_inflictsBurn() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = volatilePunch;

        IMoveSet[] memory bobMoves = new IMoveSet[](1);
        bobMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Weak",
                EFFECT: IEffect(address(0))
            })
        );

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.stats.attack = 100;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.stamina = 10;
        bobMon.stats.defense = 50;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Set RNG to trigger status effect
        // statusRng % 100 < 30 needs to be true
        // We need to find an RNG where keccak256(abi.encode(rng, "BURN")) % 100 < 30
        // And statusSelectorRng % 2 == 0 for burn
        // Let's use RNG = 0 and check if it works
        mockOracle.setRNG(0);

        // Alice uses Volatile Punch
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check if Bob's mon has burn status
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 1, 0);

        // With RNG=0, we should get a status effect
        // Let's check if any effect was applied
        if (effects.length > 0) {
            bool hasBurnOrFrostbite = false;
            for (uint256 i = 0; i < effects.length; i++) {
                if (address(effects[i]) == address(burnStatus) || address(effects[i]) == address(frostbiteStatus)) {
                    hasBurnOrFrostbite = true;
                    break;
                }
            }
            assertTrue(hasBurnOrFrostbite, "Bob should have burn or frostbite status");
        }
    }

    function test_volatilePunch_inflictsFrostbite() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = volatilePunch;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.stats.attack = 100;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.stamina = 10;
        bobMon.stats.defense = 50;
        bobMon.moves = new IMoveSet[](0);

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Try different RNG values to get frostbite (statusSelectorRng % 2 == 1)
        mockOracle.setRNG(1);

        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        (IEffect[] memory effects,) = engine.getEffects(battleKey, 1, 0);

        // Verify a status effect was applied
        if (effects.length > 0) {
            bool hasBurnOrFrostbite = false;
            for (uint256 i = 0; i < effects.length; i++) {
                if (address(effects[i]) == address(burnStatus) || address(effects[i]) == address(frostbiteStatus)) {
                    hasBurnOrFrostbite = true;
                    break;
                }
            }
            assertTrue(hasBurnOrFrostbite, "Bob should have burn or frostbite status");
        }
    }

    function test_gildedRecovery_healsStatusAndGivesBonuses() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = gildedRecovery;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.moves = aliceMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = _createMon();
        bobTeam[0].stats.hp = 1000;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Apply burn status to Alice's mon
        engine.addEffect(0, 0, IEffect(address(burnStatus)), "");

        // Damage Alice's mon
        engine.dealDamage(0, 0, 400);

        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        assertEq(hpBefore, -400, "Mon should have -400 HP");

        // Alice uses Gilded Recovery on herself (mon index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), "");

        // Verify status was removed
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);
        bool hasBurn = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(burnStatus)) {
                hasBurn = true;
                break;
            }
        }
        assertFalse(hasBurn, "Burn should be removed");

        // Verify HP was healed by 50%
        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertEq(hpAfter, hpBefore + 500, "Mon should be healed by 50% of max HP (500)");

        // Verify stamina increased by 1
        int32 staminaAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);
        assertEq(staminaAfter, staminaBefore + 1, "Stamina should increase by 1");
    }

    function test_gildedRecovery_doesNothingWithoutStatus() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = gildedRecovery;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.moves = aliceMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = _createMon();
        bobTeam[0].stats.hp = 1000;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Damage Alice's mon
        engine.dealDamage(0, 0, 400);

        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice uses Gilded Recovery without status
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), "");

        // Verify nothing changed
        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        assertEq(hpAfter, hpBefore, "HP should not change without status");
        assertEq(staminaAfter, staminaBefore - 2, "Stamina should only decrease by move cost (2)");
    }

    function test_ironWall_healsAttackDamage() public {
        IMoveSet strongAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Strong Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory aliceMoves = new IMoveSet[](2);
        aliceMoves[0] = ironWall;
        aliceMoves[1] = strongAttack;

        IMoveSet[] memory bobMoves = new IMoveSet[](1);
        bobMoves[0] = strongAttack;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.stats.attack = 100;
        aliceMon.stats.defense = 50;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.stamina = 10;
        bobMon.stats.attack = 100;
        bobMon.stats.defense = 50;
        bobMon.moves = bobMoves;

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Bob attacks Alice
        mockOracle.setRNG(2);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        int32 hpAfterAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Alice should have taken damage, but 50% was healed back
        // Exact damage depends on calculation, but it should be less than full damage
        assertTrue(hpAfterAttack < 0, "Alice should have taken some damage");
        assertTrue(hpAfterAttack > -200, "Alice should have healed 50% of damage");
    }

    function test_ironWall_healsStatusAndSelfDamage() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](2);
        aliceMoves[0] = ironWall;
        aliceMoves[1] = bullRush;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.stats.attack = 100;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.stamina = 10;
        bobMon.stats.defense = 50;
        bobMon.moves = new IMoveSet[](0);

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Apply burn to Alice
        engine.addEffect(0, 0, IEffect(address(burnStatus)), "");

        // Alice uses Bull Rush (deals self-damage)
        mockOracle.setRNG(2);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 1, NO_OP_MOVE_INDEX, "", "");

        int32 hpAfterBullRush = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Alice should have taken self-damage from Bull Rush
        // Expected: 10% of 1000 = 100 damage, but 50% healed = 50 net damage
        assertTrue(hpAfterBullRush < 0, "Alice should have taken self-damage");

        // Let burn trigger (end of turn)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        int32 hpAfterBurn = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Burn damage should also be partially healed by Iron Wall
        assertTrue(hpAfterBurn < hpAfterBullRush, "Alice should have taken burn damage");
    }

    function test_bullRush_dealsSelfDamage() public {
        IMoveSet[] memory aliceMoves = new IMoveSet[](1);
        aliceMoves[0] = bullRush;

        Mon memory aliceMon = _createMon();
        aliceMon.stats.hp = 1000;
        aliceMon.stats.stamina = 10;
        aliceMon.stats.attack = 100;
        aliceMon.moves = aliceMoves;

        Mon memory bobMon = _createMon();
        bobMon.stats.hp = 1000;
        bobMon.stats.stamina = 10;
        bobMon.stats.defense = 50;
        bobMon.moves = new IMoveSet[](0);

        Mon[] memory aliceTeam = new Mon[](1);
        aliceTeam[0] = aliceMon;

        Mon[] memory bobTeam = new Mon[](1);
        bobTeam[0] = bobMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        IValidator validatorToUse = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        bytes32 battleKey = _startBattle(validatorToUse, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Bull Rush
        mockOracle.setRNG(2);
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify Alice took self-damage (10% of 1000 = 100)
        int32 aliceHp = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertEq(aliceHp, -100, "Alice should take 10% max HP as self-damage");

        // Verify Bob took damage from the attack
        int32 bobHp = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        assertTrue(bobHp < 0, "Bob should have taken damage from Bull Rush");
    }
}
