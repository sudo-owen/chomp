// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Enums.sol";
import "../src/Structs.sol";
import "../src/Constants.sol";

import {Engine} from "../src/Engine.sol";

import {FastCommitManager} from "../src/FastCommitManager.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";
import {RandomCPU} from "../src/cpu/RandomCPU.sol";

import {StandardAttackFactory} from "../src/moves/StandardAttackFactory.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ICPURNG} from "../src/rng/ICPURNG.sol";

import {MockCPURNG} from "./mocks/MockCPURNG.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "./mocks/TestTypeCalculator.sol";

import {IAbility} from "../src/abilities/IAbility.sol";
import {IEffect} from "../src/effects/IEffect.sol";

import {GuestFeature} from "../src/mons/sofabbi/GuestFeature.sol";
import {RoundTrip} from "../src/mons/volthare/RoundTrip.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {ATTACK_PARAMS} from "../src/moves/StandardAttackStructs.sol";

contract CPUTest is Test {
    Engine engine;
    FastCommitManager commitManager;
    RandomCPU cpu;
    CPUMoveManager cpuMoveManager;
    FastValidator validator;
    DefaultRandomnessOracle defaultOracle;
    TestTypeCalculator typeCalc;
    TestTeamRegistry teamRegistry;
    MockCPURNG mockCPURNG;

    address constant ALICE = address(1);
    address constant BOB = address(2);

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        mockCPURNG = new MockCPURNG();
        cpu = new RandomCPU(2, engine, mockCPURNG);
        cpuMoveManager = new CPUMoveManager(engine, cpu);
        validator =
            new FastValidator(engine, FastValidator.Args({MONS_PER_TEAM: 4, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10}));
        typeCalc = new TestTypeCalculator();
        teamRegistry = new TestTeamRegistry();
        StandardAttackFactory attackFactory = new StandardAttackFactory(engine, typeCalc);

        IMoveSet move1 = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "m1",
                EFFECT: IEffect(address(0))
            })
        );
        IMoveSet move2 = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 0,
                STAMINA_COST: 2,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "m2",
                EFFECT: IEffect(address(0))
            })
        );
        IMoveSet roundTrip = new RoundTrip(engine, typeCalc);
        IMoveSet guestFeature = new GuestFeature(engine, typeCalc);

        IMoveSet[] memory boringMoves = new IMoveSet[](2);
        boringMoves[0] = move1;
        boringMoves[1] = move2;
        Mon memory mon1 = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: boringMoves,
            ability: IAbility(address(0))
        });
        Mon memory mon2 = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: boringMoves,
            ability: IAbility(address(0))
        });
        Mon memory mon3 = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 2,
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: boringMoves,
            ability: IAbility(address(0))
        });
        IMoveSet[] memory movesWithEffects = new IMoveSet[](2);
        movesWithEffects[0] = roundTrip;
        movesWithEffects[1] = guestFeature;
        Mon memory mon4 = Mon({
            stats: MonStats({
                hp: 1,
                stamina: 3, // Because Guest Feature costs 3
                speed: 2,
                attack: 1,
                defense: 1,
                specialAttack: 1,
                specialDefense: 1,
                type1: Type.Fire,
                type2: Type.None
            }),
            moves: movesWithEffects,
            ability: IAbility(address(0))
        });

        Mon[] memory team = new Mon[](4);
        team[0] = mon1;
        team[1] = mon2;
        team[2] = mon3;
        team[3] = mon4;

        teamRegistry.setTeam(address(cpu), team);
        teamRegistry.setTeam(ALICE, team);
    }

    /**
     * CPU should:
     * - Only swap if they are KO'ed [x]
     * - Only pick valid moves (e.g. should not pick a move that costs too much stamina) [x]
     * - Moves that need a self team index correctly generate a random index
     */
    function test_cpuOnlyPicksValidMoves() public {
        Battle memory args = Battle({
            p0: ALICE,
            p1: address(cpu),
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: teamRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), teamRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            engineHook: IEngineHook(address(0)),
            moveManager: cpuMoveManager,
            teams: new Mon[][](0),
            status: BattleProposalStatus.Proposed,
            p1TeamIndex: 0
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(
                args.validator,
                args.rngOracle,
                args.ruleset,
                args.teamRegistry,
                args.p0TeamHash,
                args.engineHook,
                args.moveManager
            )
        );
        // Call the CPU to accept the battle
        cpu.acceptBattle(battleKey, 0, battleIntegrityHash);
        // Start the battle
        engine.startBattle(battleKey, "", 0);

        // Check that the CPU enumerates mon indices 0 to 4
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 4);
        }

        // Alice selects mon 2, CPU selects mon 1
        mockCPURNG.setRNG(1);
        cpuMoveManager.selectMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(2));

        // Assert active mon index for both p0 and p1 are correct
        assertEq(engine.getActiveMonIndexForBattleState(battleKey)[0], 2);
        assertEq(engine.getActiveMonIndexForBattleState(battleKey)[1], 1);

        // Check that the CPU now has 6 moves (can swap to any one of the other 3 mons, 2 valid moves, and a no op)
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 6);
        }

        // Alice KO's the CPU's mon, the CPU chooses no op
        mockCPURNG.setRNG(0);
        cpuMoveManager.selectMove(battleKey, 0, "", "");

        // Check that the CPU now has 3 moves, all of which are switching to mon index 0, 2, or 3
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 3);
            uint256[] memory swapIds = new uint256[](3);
            swapIds[0] = 0;
            swapIds[1] = 2;
            swapIds[2] = 3;
            for (uint256 i = 0; i < swapIds.length; i++) {
                assertEq(moves[i].moveIndex, SWITCH_MOVE_INDEX);
                assertEq(abi.decode(moves[i].extraData, (uint256)), swapIds[i]);
            }
        }

        // Alice chooses no op (choice is irrelevant here), CPU chooses to switch to mon index 0
        cpuMoveManager.selectMove(battleKey, NO_OP_MOVE_INDEX, "", "");

        // Assert the CPU now has mon index 0 as the active mon
        assertEq(engine.getActiveMonIndexForBattleState(battleKey)[1], 0);

        // Assert that there are now 5 moves, switching to mon index 2, 3, the two moves, and no op
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 5);
        }

        // Alice chooses no op, CPU chooses move2 which should consume all stamina
        mockCPURNG.setRNG(4); // [no op, swap 2, swap 3, move 1, move 2, ...] and we want move 2
        // (note that the swaps are 0-indexed, and the moves are 1-indexed to refer to the above variable
        // naming convention, sorry D: )
        cpuMoveManager.selectMove(battleKey, NO_OP_MOVE_INDEX, "", "");

        // Assert that there are now 3 moves, switching to mon index 2, 3, and no op (all stamina has been consumed)
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 3);
        }

        // Alice chooses no op, CPU chooses swapping to mon index 3
        mockCPURNG.setRNG(2); // [no op, swap 2, swap 3 and we want swap 3
        cpuMoveManager.selectMove(battleKey, NO_OP_MOVE_INDEX, "", "");

        // Assert the CPU now has mon index 3 as the active mon
        assertEq(engine.getActiveMonIndexForBattleState(battleKey)[1], 3);

        // Assert that there are now 4 moves, switching to mon index 0, 2, the two moves, and no op
        // Assert that both moves generate a valid self team index (either mon 0 or mon 2)
        {
            (RevealedMove[] memory moves, ) = cpu.calculateValidMoves(battleKey, 1);
            assertEq(moves.length, 5);
            assertEq(abi.decode(moves[3].extraData, (uint256)), 0); // rng is set to 2, which % 2 is 0
            assertEq(abi.decode(moves[4].extraData, (uint256)), 0);
        }
    }

    function test_onlyP0CanAdvanceCPUMoveManager() public {
        Battle memory args = Battle({
            p0: ALICE,
            p1: address(cpu),
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: teamRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), teamRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            engineHook: IEngineHook(address(0)),
            moveManager: cpuMoveManager,
            teams: new Mon[][](0),
            status: BattleProposalStatus.Proposed,
            p1TeamIndex: 0
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(
                args.validator,
                args.rngOracle,
                args.ruleset,
                args.teamRegistry,
                args.p0TeamHash,
                args.engineHook,
                args.moveManager
            )
        );
        // Call the CPU to accept the battle
        cpu.acceptBattle(battleKey, 0, battleIntegrityHash);
        // Start the battle
        engine.startBattle(battleKey, "", 0);

        vm.startPrank(BOB);
        vm.expectRevert(CPUMoveManager.NotP0.selector);
        cpuMoveManager.selectMove(battleKey, 0, "", "");
    }
}
