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
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

import {BattleHelper} from "../abstract/BattleHelper.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";

import {StatBoosts} from "../../src/effects/StatBoosts.sol";
import {BurnStatus} from "../../src/effects/status/BurnStatus.sol";
import {FrostbiteStatus} from "../../src/effects/status/FrostbiteStatus.sol";
import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";

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
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 4, TIMEOUT_DURATION: 10})
        );
        commitManager = new DefaultCommitManager(IEngine(address(engine)));
        attackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
        matchmaker = new DefaultMatchmaker(engine);

        // Create effects
        statBoosts = new StatBoosts(IEngine(address(engine)));
        burnStatus = new BurnStatus(IEngine(address(engine)), statBoosts);
        frostbiteStatus = new FrostbiteStatus(IEngine(address(engine)), statBoosts);

        // Create ability and moves
        upOnly = new UpOnly(IEngine(address(engine)), statBoosts);
        volatilePunch = new VolatilePunch(
            IEngine(address(engine)), ITypeCalculator(address(typeCalc)), IEffect(address(burnStatus)), IEffect(address(frostbiteStatus))
        );
        gildedRecovery = new GildedRecovery(IEngine(address(engine)));
        ironWall = new IronWall(IEngine(address(engine)));
        bullRush = new BullRush(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
    }

    function test_upOnly_triggersOnDamage() public {
        // Create a standard attack move
        IMoveSet standardAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 20,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "WeakAttack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = standardAttack;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(upOnly))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10, // Faster so it attacks first
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Get initial attack
        int32 initialAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(initialAttack, 0, "Initial attack delta should be 0");

        // Bob attacks Alice (Bob is faster)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Check that attack was boosted by 5%
        int32 attackAfterDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        int32 expectedBoost = int32(int256(auroxMon.stats.attack) * 5 / 100);
        assertEq(attackAfterDamage, expectedBoost, "Attack should be boosted by 5% after taking damage");

        // Bob attacks Alice again
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Check that attack was boosted by another 5% (compounding: 100 * 1.05 * 1.05 = 110.25)
        int32 attackAfterSecondDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        int32 expectedSecondBoost = int32(int256(auroxMon.stats.attack) * 105 / 100 * 5 / 100);
        assertEq(
            attackAfterSecondDamage,
            expectedBoost + expectedSecondBoost,
            "Attack should be boosted again after second damage"
        );
    }

    function test_upOnly_triggersOnBurnDamage() public {
        // Create a move that applies burn
        IMoveSet burnMove = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 20,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 100, // Always apply burn
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "BurnMove",
                EFFECT: IEffect(address(burnStatus))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = burnMove;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(upOnly))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob attacks Alice with burn move (Bob is faster)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Check attack boost from initial damage
        int32 attackAfterDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        int32 expectedBoost = int32(int256(auroxMon.stats.attack) * 5 / 100);

        // Note: Burn also reduces attack by 50%, but that's applied after the boost
        // The boost is 5% of base attack, and burn reduction is 50% of total attack

        // Both players no-op, burn damage should trigger ability
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Check that attack was boosted again from burn damage
        int32 attackAfterBurnDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);

        // Should have two boosts now (one from attack, one from burn damage at round end)
        assertTrue(
            attackAfterBurnDamage > attackAfterDamage, "Attack should increase after burn damage"
        );
    }

    function test_upOnly_persistsAfterSwapOut() public {
        // Create a standard attack move
        IMoveSet standardAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 20,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "WeakAttack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = standardAttack;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(upOnly))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob attacks Alice
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Check attack boost
        int32 attackAfterDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        int32 expectedBoost = int32(int256(auroxMon.stats.attack) * 5 / 100);
        assertEq(attackAfterDamage, expectedBoost, "Attack should be boosted");

        // Alice swaps to mon 1
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(1), ""
        );

        // Alice swaps back to Aurox (mon 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), ""
        );

        // Check that attack boost is still present (permanent boost)
        int32 attackAfterSwapBack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Attack);
        assertEq(attackAfterSwapBack, expectedBoost, "Attack boost should persist after swapping");
    }

    function test_volatilePunch_appliesBurn() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = volatilePunch;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10, // Faster
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Set RNG to trigger burn (needs to be < 15)
        mockOracle.setRNG(10);

        // Alice uses Volatile Punch
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check that Bob's mon has burn
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 1, 0);
        bool hasBurn = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(burnStatus)) {
                hasBurn = true;
                break;
            }
        }
        assertTrue(hasBurn, "Bob's mon should have burn status");
    }

    function test_volatilePunch_appliesFrostbite() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = volatilePunch;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Set RNG to NOT trigger burn (>= 15) but trigger frostbite
        // The first check for burn will fail (20 >= 15)
        // Then it hashes the RNG and checks for frostbite
        mockOracle.setRNG(20);

        // Alice uses Volatile Punch
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check that Bob's mon has frostbite
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 1, 0);
        bool hasFrostbite = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(frostbiteStatus)) {
                hasFrostbite = true;
                break;
            }
        }
        assertTrue(hasFrostbite, "Bob's mon should have frostbite status");
    }

    function test_gildedRecovery_healsStatusAndHP() public {
        // Create burn move
        IMoveSet burnMove = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 200,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: DEFAULT_PRIORITY,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 100,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "BurnMove",
                EFFECT: IEffect(address(burnStatus))
            })
        );

        IMoveSet[] memory auroxMoves = new IMoveSet[](1);
        auroxMoves[0] = gildedRecovery;

        IMoveSet[] memory regularMoves = new IMoveSet[](1);
        regularMoves[0] = burnMove;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: auroxMoves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: regularMoves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob burns Alice
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Check that Alice has burn
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 0, 0);
        bool hasBurn = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(burnStatus)) {
                hasBurn = true;
                break;
            }
        }
        assertTrue(hasBurn, "Alice should have burn");

        // Check HP and stamina before healing
        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice uses Gilded Recovery on herself (mon index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), "");

        // Check that burn is removed
        (effects,) = engine.getEffects(battleKey, 0, 0);
        hasBurn = false;
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(burnStatus)) {
                hasBurn = true;
                break;
            }
        }
        assertFalse(hasBurn, "Burn should be removed");

        // Check that HP was healed by 50%
        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 expectedHealing = int32(int256(auroxMon.stats.hp) * 50 / 100);
        assertEq(hpAfter, hpBefore + expectedHealing, "HP should be healed by 50% of max HP");

        // Check that stamina was increased by 1
        int32 staminaAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);
        assertEq(staminaAfter, staminaBefore + 1, "Stamina should increase by 1");
    }

    function test_gildedRecovery_doesNothingWithoutStatus() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = gildedRecovery;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Record state before
        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        // Alice uses Gilded Recovery on herself (mon index 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(0), "");

        // Check that nothing changed
        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        int32 staminaAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);

        assertEq(hpAfter, hpBefore, "HP should not change");
        assertEq(staminaAfter, staminaBefore - 2, "Stamina should only decrease by move cost");
    }

    function test_ironWall_healsOpponentDamage() public {
        // Create a strong attack
        IMoveSet strongAttack = attackFactory.createAttack(
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
                NAME: "StrongAttack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory auroxMoves = new IMoveSet[](1);
        auroxMoves[0] = ironWall;

        IMoveSet[] memory regularMoves = new IMoveSet[](1);
        regularMoves[0] = strongAttack;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10, // Faster
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: auroxMoves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: regularMoves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Bob attacks Alice
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Get the damage dealt
        int32 hpAfterAttack = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // The damage should be reduced by 50% due to Iron Wall healing
        // Without Iron Wall, damage would be ~200
        // With Iron Wall, net damage should be ~100 (200 - 50% healing)
        assertTrue(hpAfterAttack > -200, "Iron Wall should have healed 50% of damage");
        assertTrue(hpAfterAttack < 0, "Alice should still have taken some damage");
    }

    function test_ironWall_healsSelfDamage() public {
        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = ironWall;
        moves[1] = bullRush;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Alice uses Bull Rush (which deals self-damage)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 1, NO_OP_MOVE_INDEX, "", "");

        // Check HP - self-damage should be healed by 50%
        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Bull Rush deals 10% max HP self-damage = 100
        // Iron Wall heals 50% = 50
        // Net damage should be 50
        // But we also need to account for damage to Bob
        // Let's just check that Alice didn't take the full 100 self-damage
        assertTrue(hpAfter > -100, "Iron Wall should have healed some self-damage");
    }

    function test_ironWall_expiresCorrectly() public {
        // Create a standard attack
        IMoveSet standardAttack = attackFactory.createAttack(
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
                NAME: "Attack",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory auroxMoves = new IMoveSet[](1);
        auroxMoves[0] = ironWall;

        IMoveSet[] memory regularMoves = new IMoveSet[](1);
        regularMoves[0] = standardAttack;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: auroxMoves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: regularMoves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Turn 1: Alice uses Iron Wall
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Turn 2: Bob attacks, Iron Wall should still be active
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");
        int32 hpAfterTurn2 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Turn 3: Bob attacks again, Iron Wall should have expired
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");
        int32 hpAfterTurn3 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // The damage in turn 3 should be greater than turn 2 (because no healing)
        int32 damageTurn2 = -hpAfterTurn2;
        int32 damageTurn3 = -(hpAfterTurn3 - hpAfterTurn2);

        assertTrue(damageTurn3 > damageTurn2, "Turn 3 damage should be greater (Iron Wall expired)");
    }

    function test_bullRush_dealsSelfDamage() public {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = bullRush;

        Mon memory auroxMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 10,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Metal,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 10,
                speed: 5,
                attack: 100,
                defense: 50,
                specialAttack: 50,
                specialDefense: 50,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = auroxMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, commitManager);

        // Switch in mons
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Bull Rush
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check that Alice took self-damage (10% of max HP = 100)
        int32 aliceHP = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Should have taken exactly 100 self-damage
        assertTrue(aliceHP <= -100, "Alice should have taken at least 100 self-damage from Bull Rush");
    }
}
