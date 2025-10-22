// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {Engine} from "../src/Engine.sol";

import {DefaultCommitManager} from "../src/DefaultCommitManager.sol";
import {DefaultValidator} from "../src/DefaultValidator.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";
import {OkayCPU} from "../src/cpu/OkayCPU.sol";

import {StandardAttackFactory} from "../src/moves/StandardAttackFactory.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";

import {MockCPURNG} from "./mocks/MockCPURNG.sol";
import {MockTypeCalculator} from "./mocks/MockTypeCalculator.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";

import {IAbility} from "../src/abilities/IAbility.sol";
import {IEffect} from "../src/effects/IEffect.sol";

import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {ATTACK_PARAMS} from "../src/moves/StandardAttackStructs.sol";

contract OkayCPUTest is Test {
    Engine engine;
    DefaultCommitManager commitManager;
    OkayCPU okayCPU;
    CPUMoveManager cpuMoveManager;
    DefaultValidator validator;
    DefaultRandomnessOracle defaultOracle;
    MockTypeCalculator typeCalc;
    TestTeamRegistry teamRegistry;
    MockCPURNG mockCPURNG;
    DefaultMatchmaker matchmaker;
    StandardAttackFactory attackFactory;

    address constant ALICE = address(1);
    address constant BOB = address(2);

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new DefaultCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        mockCPURNG = new MockCPURNG();
        typeCalc = new MockTypeCalculator();
        okayCPU = new OkayCPU(2, engine, mockCPURNG, typeCalc);
        cpuMoveManager = new CPUMoveManager(engine, okayCPU);
        validator =
            new DefaultValidator(engine, DefaultValidator.Args({MONS_PER_TEAM: 4, MOVES_PER_MON: 2, TIMEOUT_DURATION: 10}));
        teamRegistry = new TestTeamRegistry();
        matchmaker = new DefaultMatchmaker(engine);
        attackFactory = new StandardAttackFactory(engine, typeCalc);
    }

    /**
     * Helper function to create a mon with specific type and moves
     */
    function createMon(Type type1, IMoveSet[] memory moves, uint32 stamina) internal pure returns (Mon memory) {
        return Mon({
            stats: MonStats({
                hp: 10,
                stamina: stamina,
                speed: 5,
                attack: 5,
                defense: 5,
                specialAttack: 5,
                specialDefense: 5,
                type1: type1,
                type2: Type.None
            }),
            moves: moves,
            ability: IAbility(address(0))
        });
    }

    /**
     * Test 1: Type advantage switching
     * If both players have 4 mons (Nature, Fire, Yin, and Yang), and p0 has decided
     * to switch in the Nature type mon, then the CPU will opt to switch in the Fire type mon.
     */
    function test_okayCPUSwitchesInFireAgainstNature() public {
        // Set up type effectiveness: Fire is super effective (3 = 2x) against Nature
        typeCalc.setEffectiveness(Type.Fire, Type.Nature, 3);
        // Nature is not very effective (1 = 0.5x) against Fire
        typeCalc.setEffectiveness(Type.Nature, Type.Fire, 1);

        // Create moves for each mon type
        IMoveSet[] memory natureMoves = new IMoveSet[](2);
        natureMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Nature,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Nature Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        natureMoves[1] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Nature,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Nature Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory fireMoves = new IMoveSet[](2);
        fireMoves[0] = attackFactory.createAttack(
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
                NAME: "Fire Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        fireMoves[1] = attackFactory.createAttack(
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
                NAME: "Fire Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory yinMoves = new IMoveSet[](2);
        yinMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Yin,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Yin Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        yinMoves[1] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Yin,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Yin Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        IMoveSet[] memory yangMoves = new IMoveSet[](2);
        yangMoves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Yang,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Yang Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        yangMoves[1] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 1,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Yang,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Yang Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        // Create team: [Nature, Fire, Yin, Yang] for both players
        Mon[] memory team = new Mon[](4);
        team[0] = createMon(Type.Nature, natureMoves, 5);
        team[1] = createMon(Type.Fire, fireMoves, 5);
        team[2] = createMon(Type.Yin, yinMoves, 5);
        team[3] = createMon(Type.Yang, yangMoves, 5);

        teamRegistry.setTeam(ALICE, team);
        teamRegistry.setTeam(address(okayCPU), team);

        // Set up battle
        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), teamRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            p1: address(okayCPU),
            p1TeamIndex: 0,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: teamRegistry,
            engineHooks: new IEngineHook[](0),
            moveManager: cpuMoveManager,
            matchmaker: okayCPU
        });

        vm.startPrank(ALICE);
        // Authorize the CPU as a matchmaker
        address[] memory makersToAdd = new address[](1);
        makersToAdd[0] = address(okayCPU);
        address[] memory makersToRemove = new address[](0);
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(address(okayCPU));
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(ALICE);
        // Start the battle
        bytes32 battleKey = okayCPU.startBattle(proposal);

        // Alice selects Nature mon (index 0)
        // The CPU should respond by selecting Fire mon (index 1) since Fire resists Nature
        cpuMoveManager.selectMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(0));

        // Check that the CPU selected Fire mon (index 1)
        uint256[] memory activeMonIndices = engine.getActiveMonIndexForBattleState(battleKey);
        assertEq(activeMonIndices[0], 0, "Alice should have Nature mon active (index 0)");
        assertEq(activeMonIndices[1], 1, "CPU should have Fire mon active (index 1)");
    }

    /**
     * Test 2: Low stamina behavior
     * If the CPU's active mon has a staminaDelta of -3 or lower, then we should either
     * no-op (75% chance) or swap (25% chance), depending on the RNG.
     */
    function test_okayCPULowStaminaBehavior() public {
        // Create moves with stamina cost of 2 each
        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 2,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        moves[1] = attackFactory.createAttack(
            ATTACK_PARAMS({
                BASE_POWER: 1,
                STAMINA_COST: 2,
                ACCURACY: 100,
                PRIORITY: 1,
                MOVE_TYPE: Type.Fire,
                EFFECT_ACCURACY: 0,
                MOVE_CLASS: MoveClass.Physical,
                CRIT_RATE: 0,
                VOLATILITY: 0,
                NAME: "Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        // Create team with mons that have 5 stamina (so after 2 uses of 2-cost moves, staminaDelta = -4)
        Mon[] memory team = new Mon[](4);
        for (uint256 i = 0; i < 4; i++) {
            team[i] = createMon(Type.Fire, moves, 5);
        }

        teamRegistry.setTeam(ALICE, team);
        teamRegistry.setTeam(address(okayCPU), team);

        // Set up battle
        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), teamRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            p1: address(okayCPU),
            p1TeamIndex: 0,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: teamRegistry,
            engineHooks: new IEngineHook[](0),
            moveManager: cpuMoveManager,
            matchmaker: okayCPU
        });

        vm.startPrank(ALICE);
        address[] memory makersToAdd = new address[](1);
        makersToAdd[0] = address(okayCPU);
        address[] memory makersToRemove = new address[](0);
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(address(okayCPU));
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(ALICE);
        bytes32 battleKey = okayCPU.startBattle(proposal);

        // Initial switch - both select mon 0
        cpuMoveManager.selectMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(0));

        // Execute turn 1 - CPU uses move 0 (costs 2 stamina, staminaDelta = -2)
        cpuMoveManager.selectMove(battleKey, 0, "", "");

        // Execute turn 2 - CPU uses move 1 (costs 2 stamina, staminaDelta = -4)
        cpuMoveManager.selectMove(battleKey, 1, "", "");

        // Verify stamina is now -4
        int32 staminaDelta = engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.Stamina);
        assertEq(staminaDelta, -4, "CPU mon should have staminaDelta of -4");

        // Test case 1: RNG % 4 != 0, should return no-op (75% chance)
        mockCPURNG.setRNG(1); // 1 % 4 = 1, not equal to 0
        (uint256 moveIndex, bytes memory extraData) = okayCPU.selectMove(battleKey, 1);
        assertEq(moveIndex, NO_OP_MOVE_INDEX, "CPU should select no-op when RNG % 4 != 0 and stamina is low");

        // Test case 2: RNG % 4 == 0, should return switch (25% chance)
        mockCPURNG.setRNG(4); // 4 % 4 = 0
        (moveIndex, extraData) = okayCPU.selectMove(battleKey, 1);
        assertEq(moveIndex, SWITCH_MOVE_INDEX, "CPU should select switch when RNG % 4 == 0 and stamina is low");
    }

    /**
     * Test 3: Smart select weighted random selection
     * The smart select should work as expected, with greater weight on the moves,
     * and less weight on switches or no ops.
     */
    function test_okayCPUSmartSelectWeighting() public {
        // Create moves
        IMoveSet[] memory moves = new IMoveSet[](2);
        moves[0] = attackFactory.createAttack(
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
                NAME: "Attack 1",
                EFFECT: IEffect(address(0))
            })
        );
        moves[1] = attackFactory.createAttack(
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
                NAME: "Attack 2",
                EFFECT: IEffect(address(0))
            })
        );

        // Create team
        Mon[] memory team = new Mon[](4);
        for (uint256 i = 0; i < 4; i++) {
            team[i] = createMon(Type.Fire, moves, 10);
        }

        teamRegistry.setTeam(ALICE, team);
        teamRegistry.setTeam(address(okayCPU), team);

        // Set up battle
        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), teamRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            p1: address(okayCPU),
            p1TeamIndex: 0,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: teamRegistry,
            engineHooks: new IEngineHook[](0),
            moveManager: cpuMoveManager,
            matchmaker: okayCPU
        });

        vm.startPrank(ALICE);
        address[] memory makersToAdd = new address[](1);
        makersToAdd[0] = address(okayCPU);
        address[] memory makersToRemove = new address[](0);
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(address(okayCPU));
        engine.updateMatchmakers(makersToAdd, makersToRemove);

        vm.startPrank(ALICE);
        bytes32 battleKey = okayCPU.startBattle(proposal);

        // Initial switch
        cpuMoveManager.selectMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(0));

        // Test the smart select weighting
        // With 2 moves, adjustedTotalMovesDenom = 3
        // If RNG % 3 == 0, should select switch or no-op
        // If RNG % 3 != 0, should select a move

        // Test case 1: RNG % 3 == 0, should select switch or no-op
        mockCPURNG.setRNG(0); // First RNG call: 0 % 3 = 0 (trigger switch/no-op path)
        cpuMoveManager.selectMove(battleKey, NO_OP_MOVE_INDEX, "", "");

        (uint256 moveIndex, bytes memory extraData) = okayCPU.selectMove(battleKey, 1);
        // Should be either NO_OP_MOVE_INDEX or SWITCH_MOVE_INDEX
        assertTrue(
            moveIndex == NO_OP_MOVE_INDEX || moveIndex == SWITCH_MOVE_INDEX,
            "When RNG % 3 == 0, should select no-op or switch"
        );

        // Test case 2: RNG % 3 != 0, should select a move
        mockCPURNG.setRNG(1); // First RNG call: 1 % 3 = 1 (trigger move path)
        (moveIndex, extraData) = okayCPU.selectMove(battleKey, 1);
        // Should be a valid move index (0 or 1)
        assertTrue(moveIndex == 0 || moveIndex == 1, "When RNG % 3 != 0, should select a move");

        // Test case 3: Another non-zero case
        mockCPURNG.setRNG(2); // First RNG call: 2 % 3 = 2 (trigger move path)
        (moveIndex, extraData) = okayCPU.selectMove(battleKey, 1);
        assertTrue(moveIndex == 0 || moveIndex == 1, "When RNG % 3 != 0, should select a move");
    }
}
