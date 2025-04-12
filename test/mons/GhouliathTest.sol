// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Structs.sol";
import {Test} from "forge-std/Test.sol";

import {Engine} from "../../src/Engine.sol";
import {EffectStep, MonStateIndexName, MoveClass, Type} from "../../src/Enums.sol";
import {FastCommitManager} from "../../src/FastCommitManager.sol";

import {FastValidator} from "../../src/FastValidator.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IFastCommitManager} from "../../src/IFastCommitManager.sol";
import {IRuleset} from "../../src/IRuleset.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";

import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";
import {ITeamRegistry} from "../../src/teams/ITeamRegistry.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {BattleHelper} from "../abstract/BattleHelper.sol";

import {RiseFromTheGrave} from "../../src/mons/ghouliath/RiseFromTheGrave.sol";
import {Osteoporosis} from "../../src/mons/ghouliath/Osteoporosis.sol";
import {WitherAway} from "../../src/mons/ghouliath/WitherAway.sol";
import {PanicStatus} from "../../src/effects/status/PanicStatus.sol";

contract GhouliathTest is Test, BattleHelper {
    Engine engine;
    FastCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    FastValidator validator;
    RiseFromTheGrave riseFromTheGrave;
    Osteoporosis osteoporosis;
    WitherAway witherAway;
    PanicStatus panicStatus;
    StandardAttackFactory standardAttackFactory;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );
        commitManager = new FastCommitManager(IEngine(address(engine)));
        engine.setCommitManager(address(commitManager));
        riseFromTheGrave = new RiseFromTheGrave(IEngine(address(engine)));
        osteoporosis = new Osteoporosis(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
        panicStatus = new PanicStatus(IEngine(address(engine)));
        witherAway = new WitherAway(IEngine(address(engine)), ITypeCalculator(address(typeCalc)), IEffect(address(panicStatus)));
        standardAttackFactory = new StandardAttackFactory(IEngine(address(engine)), ITypeCalculator(address(typeCalc)));
    }

    /*
    Test that:
    - The effect is applied when the mon switches in
    - When the mon is KO'd, the effect is removed from the mon and added as a global effect
    - After the revival delay, the mon is revived
    - The effect is only applied once per battle
    - The global effect is cleared after revival
    */
    function testRiseFromTheGrave() public {
        // Create a team with a mon that has RiseFromTheGrave ability
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = standardAttackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                MOVE_CLASS: MoveClass.Physical,
                NAME: "Attack",
                EFFECT: IEffect(address(0)),
                EFFECT_ACCURACY: 0,
                CRIT_RATE: 0,
                VOLATILITY: 0
            })
        );
        Mon memory ghouliathMon = Mon({
            stats: MonStats({
                hp: 100,
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
            ability: IAbility(address(riseFromTheGrave))
        });

        // Create a regular mon for the opponent
        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 100,
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

        // Create teams
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = ghouliathMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: mockOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            )
        });
        vm.prank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.prank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.prank(ALICE);
        engine.startBattle(battleKey, "", 0);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify that the RiseFromTheGrave effect applies its global effect and KV
        bytes32 monEffectId = keccak256(abi.encode(0, 0, riseFromTheGrave.name()));
        bytes32 effectValue = engine.getGlobalKV(battleKey, monEffectId);
        assertEq(uint256(effectValue), 1, "RiseFromTheGrave effect should be applied on switch in");

        // Bob uses the attack (which KOs) on Alice's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Verify Alice's mon is KO'd
        int32 isKnockedOut = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKnockedOut, 1);

        // Verify the effect is added to the global effects list
        (IEffect[] memory effects,) = engine.getEffects(battleKey, 2, 0);
        assertEq(
            address(effects[0]), address(riseFromTheGrave), "RiseFromTheGrave effect should be added to global effects"
        );

        // Alice swaps in mon index 1
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(1), true);

        // We wait for the REVIVAL_DELAY - 1 turns to pass
        for (uint256 i = 0; i < riseFromTheGrave.REVIVAL_DELAY() - 1; i++) {
            _commitRevealExecuteForAliceAndBob(
                engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", ""
            );
        }

        // Verify mon is revived
        isKnockedOut = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKnockedOut, 0, "Alice's mon should be revived");

        // Alice swaps in mon index 0, Bob does attack again, which KOs Alice's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 0, abi.encode(0), "");

        // Verify the mon is not revived after REVIVAL_DELAY turns
        // (First we swap in mon index 1)
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(1), true);
        for (uint256 i = 0; i < riseFromTheGrave.REVIVAL_DELAY() - 1; i++) {
            _commitRevealExecuteForAliceAndBob(
                engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", ""
            );
        }

        // Verify mon is not revived
        isKnockedOut = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKnockedOut, 1, "Alice's mon should be revived");
    }

    function testDoubleRiseFromTheGrave() public {

        // Create a team with a mon that has RiseFromTheGrave ability
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = standardAttackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 100,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                MOVE_CLASS: MoveClass.Physical,
                NAME: "Attack",
                EFFECT: IEffect(address(0)),
                EFFECT_ACCURACY: 0,
                CRIT_RATE: 0,
                VOLATILITY: 0
            })
        );
        Mon memory ghouliathMon = Mon({
            stats: MonStats({
                hp: 100,
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
            ability: IAbility(address(riseFromTheGrave))
        });

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = ghouliathMon;
        aliceTeam[1] = ghouliathMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = ghouliathMon;
        bobTeam[1] = ghouliathMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: mockOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            )
        });
        vm.prank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.prank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.prank(ALICE);
        engine.startBattle(battleKey, "", 0);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Bob uses the attack (which KOs) on Alice's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 0, "", "");

        // Alice swaps in mon index 1
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(1), true);

        // Alice KOs Bob's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Bob swaps in mon index 1
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(1), true);

        // We wait for the REVIVAL_DELAY turns to pass
        for (uint256 i = 0; i < riseFromTheGrave.REVIVAL_DELAY() - 1; i++) {
            _commitRevealExecuteForAliceAndBob(
                engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", ""
            );
        }

        // Verify Alice's mon is revived
        int32 isKnockedOut = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKnockedOut, 0, "Alice's mon should be revived");

        // Verify Bob's mon is revived
        isKnockedOut = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKnockedOut, 0, "Bob's mon should be revived");
    }

    function testWitherAway() public {
        // Create a team with a mon that has WitherAway move
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = witherAway;

        // Create a mon with specific stats
        Mon memory attackerMon = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 10,
                speed: 10, // Higher speed to go first
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Yang,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        // Create a regular mon for the opponent
        Mon memory defenderMon = Mon({
            stats: MonStats({
                hp: 100,
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

        // Create teams
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = attackerMon;
        aliceTeam[1] = attackerMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = defenderMon;
        bobTeam[1] = defenderMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: mockOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            )
        });
        vm.prank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.prank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.prank(ALICE);
        engine.startBattle(battleKey, "", 0);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses WitherAway on Bob's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Verify that both mons have the PanicStatus effect applied
        (IEffect[] memory aliceEffects,) = engine.getEffects(battleKey, 0, 0);
        (IEffect[] memory bobEffects,) = engine.getEffects(battleKey, 1, 0);

        // Check that both mons have at least one effect
        assertGt(aliceEffects.length, 0, "Alice's mon should have at least one effect");
        assertGt(bobEffects.length, 0, "Bob's mon should have at least one effect");

        // Check that the effect is PanicStatus
        bool aliceHasPanic = false;
        bool bobHasPanic = false;

        for (uint256 i = 0; i < aliceEffects.length; i++) {
            if (keccak256(abi.encodePacked(aliceEffects[i].name())) == keccak256(abi.encodePacked("Panic"))) {
                aliceHasPanic = true;
                break;
            }
        }

        for (uint256 i = 0; i < bobEffects.length; i++) {
            if (keccak256(abi.encodePacked(bobEffects[i].name())) == keccak256(abi.encodePacked("Panic"))) {
                bobHasPanic = true;
                break;
            }
        }

        assertTrue(aliceHasPanic, "Alice's mon should have Panic status");
        assertTrue(bobHasPanic, "Bob's mon should have Panic status");

        // Verify that stamina is reduced at the end of the turn due to Panic status
        int32 aliceStaminaDelta = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Stamina);
        int32 bobStaminaDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Stamina);

        // Alice used the move (costs 3 stamina) and got panic (costs 1 more), so -4 total
        assertEq(aliceStaminaDelta, -4, "Alice's mon should have lost 4 stamina");
        // Bob got panic (costs 1 stamina)
        assertEq(bobStaminaDelta, -1, "Bob's mon should have lost 1 stamina");
    }

    function testOsteoporosis() public {
        // Create a team with a mon that has Osteoporosis move
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = osteoporosis;

        // Create a mon with specific stats to make damage calculation predictable
        Mon memory attackerMon = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 10,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Yang,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        // Create a regular mon for the opponent with known defense
        Mon memory defenderMon = Mon({
            stats: MonStats({
                hp: 100,
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

        // Create teams
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = attackerMon;
        aliceTeam[1] = attackerMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = defenderMon;
        bobTeam[1] = defenderMon;

        // Register teams
        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: mockOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            )
        });
        vm.prank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.prank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.prank(ALICE);
        engine.startBattle(battleKey, "", 0);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses Osteoporosis on Bob's mon
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Calculate the damage dealt
        uint32 damageTaken = uint32(-1 * engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp));

        // Assert it's at least base power / 2
        assertGe(damageTaken, osteoporosis.basePower(battleKey) / 2, "Damage taken should be at least base power / 2");
    }
}
