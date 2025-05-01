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
import {IFastCommitManager} from "../../src/IFastCommitManager.sol";
import {IRuleset} from "../../src/IRuleset.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {TypeCalculator} from "../../src/types/TypeCalculator.sol";
import {ITeamRegistry} from "../../src/teams/ITeamRegistry.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";
import {StandardAttackFactory} from "../../src/moves/StandardAttackFactory.sol";
import {StandardAttack} from "../../src/moves/StandardAttack.sol";
import {ATTACK_PARAMS} from "../../src/moves/StandardAttackStructs.sol";

import {BattleHelper} from "../abstract/BattleHelper.sol";

import {CarrotHarvest} from "../../src/mons/sofabbi/CarrotHarvest.sol";
import {GuestFeature} from "../../src/mons/sofabbi/GuestFeature.sol";
import {SnackBreak} from "../../src/mons/sofabbi/SnackBreak.sol";
import {Gachachacha} from "../../src/mons/sofabbi/Gachachacha.sol";

contract SofabbiTest is Test, BattleHelper {
    Engine engine;
    FastCommitManager commitManager;
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;
    TestTeamRegistry defaultRegistry;
    CarrotHarvest carrotHarvest;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();
        defaultRegistry = new TestTeamRegistry();
        engine = new Engine();
        commitManager = new FastCommitManager(IEngine(address(engine)));
        engine.setCommitManager(address(commitManager));

        // Initialize the CarrotHarvest ability
        carrotHarvest = new CarrotHarvest(IEngine(address(engine)));
    }

    function test_carrotHarvestAppliesOnSwitchIn() public {
        FastValidator validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 0, TIMEOUT_DURATION: 10})
        );
        // Create move arrays
        IMoveSet[] memory moves = new IMoveSet[](0);

        // Create a mon with CarrotHarvest ability
        Mon memory sofabbiMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Nature,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(carrotHarvest))
        });

        // Create a second mon without the ability
        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 10,
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

        // Create teams with two mons each
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = sofabbiMon;
        aliceTeam[1] = regularMon;

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = regularMon;
        bobTeam[1] = regularMon;

        // Register teams
        defaultRegistry.setTeam(BattleHelper.ALICE, aliceTeam);
        defaultRegistry.setTeam(BattleHelper.BOB, bobTeam);

        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: BattleHelper.ALICE,
            p1: BattleHelper.BOB,
            validator: validator,
            rngOracle: mockOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(
                    bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(BattleHelper.ALICE, 0)
                )
            )
        });

        vm.prank(BattleHelper.ALICE);
        bytes32 battleKey = engine.proposeBattle(args);

        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );

        vm.prank(BattleHelper.BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);

        vm.prank(BattleHelper.ALICE);
        engine.startBattle(battleKey, "", 0);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify that the CarrotHarvest effect was applied to Alice's mon
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].targetedEffects.length, 1);

        // Now have Alice switch to her second mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(1), ""
        );

        // Now have Alice switch back to her first mon
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, NO_OP_MOVE_INDEX, abi.encode(0), ""
        );

        // Verify that the CarrotHarvest effect is still only applied once
        // (should still have only one targeted effect)
        assertEq(state.monStates[0][0].targetedEffects.length, 1);

        // Verify the global KV store has the effect registered
        bytes32 monId = keccak256(abi.encode(0, 0, "Carrot Harvest"));
        bytes32 value = engine.getGlobalKV(battleKey, monId);
        assertEq(uint256(value), 1);
    }

    function test_carrotHarvestTriggersAtEndOfRoundWhenRNGReturnsTrue() public {
        FastValidator validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 0, TIMEOUT_DURATION: 10})
        );

        // Create move arrays
        IMoveSet[] memory moves = new IMoveSet[](0);

        // Create a mon with CarrotHarvest ability
        Mon memory sofabbiMon = Mon({
            stats: MonStats({
                hp: 10,
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Nature,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(carrotHarvest))
        });
        Mon memory regularMon = Mon({
            stats: MonStats({
                hp: 10,
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

        // Set up teams
        Mon[] memory team = new Mon[](2);
        team[0] = sofabbiMon;
        team[1] = regularMon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        // Start battle
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

        // Set oracle to return 1 (ie both mons gain staminaDelta)
        mockOracle.setRNG(1);

        // First move: Both players select their first mon (index 0)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Verify that staminaDelta is 1 for both mons
        BattleState memory state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].staminaDelta, 1);
        assertEq(state.monStates[1][0].staminaDelta, 1);

        // Set oracle to return 0 (ie no mons gain staminaDelta)
        mockOracle.setRNG(0);

        // Alice and Bob both do nothing
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, NO_OP_MOVE_INDEX, "", "");

        // Verify that staminaDelta is still 1 for both mons
        state = engine.getBattleState(battleKey);
        assertEq(state.monStates[0][0].staminaDelta, 1);
        assertEq(state.monStates[1][0].staminaDelta, 1);
    }

    function test_guestFeature() public {
        TypeCalculator calc = new TypeCalculator();
        FastValidator validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 4, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );

        GuestFeature gf = new GuestFeature(engine, calc);
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = gf;

        /**
            Air (defender)
            Ice (2x)
            Earth (0x)
            Nature (1/2x)
        */

        Mon memory airMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 100,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Air,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon memory iceMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Ice,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon memory earthMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Earth,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        Mon memory natureMon = Mon({
            stats: MonStats({
                hp: 1000,
                stamina: 5,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Nature,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory team = new Mon[](4);
        team[0] = airMon;
        team[1] = iceMon;
        team[2] = earthMon;
        team[3] = natureMon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry);

        // First move: Both players select their first mon (index 0, the Air mon)
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Damage is returned in negative, so that's why there are some weird sign cancellations below

        // Alice uses Guest Feature targeting mon index 1, it should deal 2x damage
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(1), abi.encode(0)
        );
        int32 bobDmg = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        assertApproxEqRel(-1 * bobDmg, int32(2 * gf.BASE_POWER()), 2e17);

        // Alice uses Guest Feature targeting mon index 2, it should deal 0 damage
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(2), abi.encode(0)
        );
        int32 newBobDmg = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        assertEq(newBobDmg, bobDmg, "No damage");

        // Alice uses Guest Feature targeting mon index 3, it should deal 1/2 damage
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, abi.encode(3), abi.encode(0)
        );
        newBobDmg = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        bobDmg = bobDmg - newBobDmg;
        assertApproxEqRel(bobDmg, int32(gf.BASE_POWER()/2), 2e17);

    }

    function test_snackBreak() public {
        FastValidator validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 1, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10})
        );
        StandardAttackFactory attackFactory = new StandardAttackFactory(IEngine(address(engine)), typeCalc);
        SnackBreak sb = new SnackBreak(engine);
        StandardAttack bigAttack = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 127,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 0,
                MOVE_TYPE: Type.Water,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "foo",
                EFFECT: IEffect(address(0))
            })
        );
        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = sb;
        moves[1] = bigAttack;
        Mon memory chunkyMon = Mon({
            stats: MonStats({
                hp: 128,
                stamina: 10,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Nature,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });

        Mon[] memory team = new Mon[](1);
        team[0] = chunkyMon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry);

        // Both players send in mon index 0
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Alice uses nothing, Bob uses move index 1, puts Alice at 1 HP
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 1, "", ""
        );

        int32 hpBefore = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        // Alice uses Snack Break, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );

        int32 hpAfter = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        assertEq(hpAfter - hpBefore, 64, "Healing worked");

        // Alice uses Snack Break, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );

        int32 hpAfter2 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        assertEq(hpAfter2 - hpAfter, 32, "Healing worked, went down");

        // Alice uses Snack Break, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );

        int32 hpAfter3 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        assertEq(hpAfter3 - hpAfter2, 16, "Healing worked, went down");

        // Alice uses Snack Break, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );

        int32 hpAfter4 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        assertEq(hpAfter4 - hpAfter3, 8, "Healing worked, went down");

        // Alice uses Snack Break, Bob does nothing
        _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", ""
        );

        int32 hpAfter5 = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);

        assertEq(hpAfter5, 0, "All healed up");
    }

    function test_gachachacha() public {
        Gachachacha gacha = new Gachachacha(engine, typeCalc);
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = gacha;
        Mon memory mon = Mon({
            stats: MonStats({
                hp: 1024,
                stamina: 100,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: Type.Nature,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
        FastValidator validator = new FastValidator(
            IEngine(address(engine)), FastValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );
        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry);

        // Both players send in mon index 0
         _commitRevealExecuteForAliceAndBob(
            engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0)
        );

        // Set rng to be 10
        mockOracle.setRNG(10);

        // Alice uses an attack, it should do minimal damage
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");

        // Check damage dealt to Bob
        int32 bobDamage = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);

        assertApproxEqRel(bobDamage, -10, 2e17, "low damage from rng");

        // Set rng to be MAX BASE POWER
        mockOracle.setRNG(gacha.MAX_BASE_POWER() + 1);

        // Alice uses an attack, it should hurt themselves for a lot
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");
        int32 aliceDamage = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.Hp);
        assertApproxEqRel(aliceDamage, -1024, 2e17, "high self damage from rng");

        // Set rng to be MAX BASE POWER + SELF KO CHANCE + 1
        mockOracle.setRNG(gacha.SELF_KO_THRESHOLD_R() + 1);

        // Opponent should be close to death (maybe not due to variance)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, NO_OP_MOVE_INDEX, "", "");
        bobDamage = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Hp);
        assertApproxEqRel(bobDamage, -1024, 2e17, "low damage from rng");
    }
}
