// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";

import "../../src/Constants.sol";
import "../../src/Enums.sol";
import "../../src/Structs.sol";

import {DefaultCommitManager} from "../../src/DefaultCommitManager.sol";
import {Engine} from "../../src/Engine.sol";
import {DefaultValidator} from "../../src/DefaultValidator.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IAbility} from "../../src/abilities/IAbility.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {MockRandomnessOracle} from "../mocks/MockRandomnessOracle.sol";
import {TestTeamRegistry} from "../mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "../mocks/TestTypeCalculator.sol";

import {StatBoosts} from "../../src/effects/StatBoosts.sol";
import {StatBoostsKV} from "../../src/effects/StatBoostsKV.sol";
import {StatBoostsMove} from "../mocks/StatBoostsMove.sol";
import {StatBoostsMoveKV} from "../mocks/StatBoostsMoveKV.sol";

import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";
import {BattleHelper} from "../abstract/BattleHelper.sol";

/**
 * Gas comparison test for StatBoosts vs StatBoostsKV
 *
 * Scenarios tested:
 * 1. First boost (cold storage)
 * 2. Second boost from same source (merge)
 * 3. Third boost from different source
 * 4. OnMonSwitchOut with multiple temp boosts
 * 5. Multiple different sources (3, 5 boosts)
 */
contract StatBoostsGasComparisonTest is Test, BattleHelper {
    // Original implementation
    Engine engineOriginal;
    DefaultCommitManager commitManagerOriginal;
    TestTeamRegistry registryOriginal;
    IValidator validatorOriginal;
    StatBoosts statBoostsOriginal;
    StatBoostsMove statBoostMoveOriginal;
    DefaultMatchmaker matchmakerOriginal;

    // KV implementation
    Engine engineKV;
    DefaultCommitManager commitManagerKV;
    TestTeamRegistry registryKV;
    IValidator validatorKV;
    StatBoostsKV statBoostsKV;
    StatBoostsMoveKV statBoostMoveKV;
    DefaultMatchmaker matchmakerKV;

    // Shared
    TestTypeCalculator typeCalc;
    MockRandomnessOracle mockOracle;

    function setUp() public {
        typeCalc = new TestTypeCalculator();
        mockOracle = new MockRandomnessOracle();

        // Setup original implementation
        registryOriginal = new TestTeamRegistry();
        engineOriginal = new Engine();
        validatorOriginal = new DefaultValidator(
            IEngine(address(engineOriginal)),
            DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );
        commitManagerOriginal = new DefaultCommitManager(IEngine(address(engineOriginal)));
        statBoostsOriginal = new StatBoosts(IEngine(address(engineOriginal)));
        statBoostMoveOriginal = new StatBoostsMove(IEngine(address(engineOriginal)), statBoostsOriginal);
        matchmakerOriginal = new DefaultMatchmaker(engineOriginal);

        // Setup KV implementation
        registryKV = new TestTeamRegistry();
        engineKV = new Engine();
        validatorKV = new DefaultValidator(
            IEngine(address(engineKV)),
            DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 1, TIMEOUT_DURATION: 10})
        );
        commitManagerKV = new DefaultCommitManager(IEngine(address(engineKV)));
        statBoostsKV = new StatBoostsKV(IEngine(address(engineKV)));
        statBoostMoveKV = new StatBoostsMoveKV(IEngine(address(engineKV)), statBoostsKV);
        matchmakerKV = new DefaultMatchmaker(engineKV);
    }

    function _createTeams(IMoveSet move) internal pure returns (Mon[] memory) {
        IMoveSet[] memory moves = new IMoveSet[](1);
        moves[0] = move;

        Mon memory mon = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 100,
                speed: 100,
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

        Mon[] memory team = new Mon[](2);
        team[0] = mon;
        team[1] = mon;
        return team;
    }

    function _setupBattleOriginal() internal returns (bytes32 battleKey) {
        Mon[] memory team = _createTeams(statBoostMoveOriginal);
        registryOriginal.setTeam(ALICE, team);
        registryOriginal.setTeam(BOB, team);

        battleKey = _startBattle(
            validatorOriginal,
            engineOriginal,
            mockOracle,
            registryOriginal,
            matchmakerOriginal,
            address(commitManagerOriginal)
        );

        // Both players select mon 0
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKey,
            SWITCH_MOVE_INDEX,
            SWITCH_MOVE_INDEX,
            abi.encode(0),
            abi.encode(0)
        );
    }

    function _setupBattleKV() internal returns (bytes32 battleKey) {
        Mon[] memory team = _createTeams(statBoostMoveKV);
        registryKV.setTeam(ALICE, team);
        registryKV.setTeam(BOB, team);

        battleKey = _startBattle(
            validatorKV,
            engineKV,
            mockOracle,
            registryKV,
            matchmakerKV,
            address(commitManagerKV)
        );

        // Both players select mon 0
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKey,
            SWITCH_MOVE_INDEX,
            SWITCH_MOVE_INDEX,
            abi.encode(0),
            abi.encode(0)
        );
    }

    function test_gasComparison_firstBoost() public {
        console.log("\n=== First Boost (Cold Storage) ===");

        // Original
        bytes32 battleKeyOrig = _setupBattleOriginal();
        uint256 gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        uint256 gasOriginal = gasBefore - gasleft();

        // KV
        bytes32 battleKeyKV = _setupBattleKV();
        gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        uint256 gasKV = gasBefore - gasleft();

        console.log("Original: %d gas", gasOriginal);
        console.log("KV:       %d gas", gasKV);
        console.log("Delta:    %s%d gas", gasKV > gasOriginal ? "+" : "-", gasKV > gasOriginal ? gasKV - gasOriginal : gasOriginal - gasKV);

        // Verify correctness
        int32 statOrig = engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Attack);
        int32 statKV = engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Attack);
        assertEq(statOrig, statKV, "Stats should match");
    }

    function test_gasComparison_secondBoostSameSource() public {
        console.log("\n=== Second Boost (Same Source, Merge) ===");

        // Original - setup and first boost
        bytes32 battleKeyOrig = _setupBattleOriginal();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );

        // Original - second boost
        uint256 gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        uint256 gasOriginal = gasBefore - gasleft();

        // KV - setup and first boost
        bytes32 battleKeyKV = _setupBattleKV();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );

        // KV - second boost
        gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        uint256 gasKV = gasBefore - gasleft();

        console.log("Original: %d gas", gasOriginal);
        console.log("KV:       %d gas", gasKV);
        console.log("Delta:    %s%d gas", gasKV > gasOriginal ? "+" : "-", gasKV > gasOriginal ? gasKV - gasOriginal : gasOriginal - gasKV);

        // Verify correctness
        int32 statOrig = engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Attack);
        int32 statKV = engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Attack);
        assertEq(statOrig, statKV, "Stats should match");
    }

    function test_gasComparison_thirdBoostDifferentStat() public {
        console.log("\n=== Third Boost (Different Stat) ===");

        // Original - setup and two boosts
        bytes32 battleKeyOrig = _setupBattleOriginal();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );

        // Original - third boost to different stat
        uint256 gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(20)),
            ""
        );
        uint256 gasOriginal = gasBefore - gasleft();

        // KV - setup and two boosts
        bytes32 battleKeyKV = _setupBattleKV();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );

        // KV - third boost to different stat
        gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(20)),
            ""
        );
        uint256 gasKV = gasBefore - gasleft();

        console.log("Original: %d gas", gasOriginal);
        console.log("KV:       %d gas", gasKV);
        console.log("Delta:    %s%d gas", gasKV > gasOriginal ? "+" : "-", gasKV > gasOriginal ? gasKV - gasOriginal : gasOriginal - gasKV);

        // Verify correctness
        int32 atkOrig = engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Attack);
        int32 atkKV = engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Attack);
        assertEq(atkOrig, atkKV, "Attack stats should match");

        int32 defOrig = engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Defense);
        int32 defKV = engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Defense);
        assertEq(defOrig, defKV, "Defense stats should match");
    }

    function test_gasComparison_switchOutWithBoosts() public {
        console.log("\n=== Switch Out (Remove Temp Boosts) ===");

        // Original - setup and add 3 boosts to different stats
        bytes32 battleKeyOrig = _setupBattleOriginal();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(15)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Speed), int32(20)),
            ""
        );

        // Original - switch out
        uint256 gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            SWITCH_MOVE_INDEX,
            NO_OP_MOVE_INDEX,
            abi.encode(1),
            ""
        );
        uint256 gasOriginal = gasBefore - gasleft();

        // KV - setup and add 3 boosts to different stats
        bytes32 battleKeyKV = _setupBattleKV();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(15)),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            0,
            NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Speed), int32(20)),
            ""
        );

        // KV - switch out
        gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            SWITCH_MOVE_INDEX,
            NO_OP_MOVE_INDEX,
            abi.encode(1),
            ""
        );
        uint256 gasKV = gasBefore - gasleft();

        console.log("Original: %d gas", gasOriginal);
        console.log("KV:       %d gas", gasKV);
        console.log("Delta:    %s%d gas", gasKV > gasOriginal ? "+" : "-", gasKV > gasOriginal ? gasKV - gasOriginal : gasOriginal - gasKV);

        // Verify boosts were removed (switch back and check stats are reset)
        _commitRevealExecuteForAliceAndBob(
            engineOriginal,
            commitManagerOriginal,
            battleKeyOrig,
            SWITCH_MOVE_INDEX,
            NO_OP_MOVE_INDEX,
            abi.encode(0),
            ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV,
            commitManagerKV,
            battleKeyKV,
            SWITCH_MOVE_INDEX,
            NO_OP_MOVE_INDEX,
            abi.encode(0),
            ""
        );

        int32 atkOrig = engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Attack);
        int32 atkKV = engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Attack);
        assertEq(atkOrig, 0, "Original: Attack should be reset after switch");
        assertEq(atkKV, 0, "KV: Attack should be reset after switch");
    }

    function test_gasComparison_effectCount() public {
        console.log("\n=== Effect Array Size After 5 Boosts ===");

        // Original - setup and add 5 boosts to different stats
        bytes32 battleKeyOrig = _setupBattleOriginal();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(15)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Speed), int32(20)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.SpecialAttack), int32(10)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.SpecialDefense), int32(10)), ""
        );

        // KV - same boosts
        bytes32 battleKeyKV = _setupBattleKV();
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Defense), int32(15)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Speed), int32(20)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.SpecialAttack), int32(10)), ""
        );
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.SpecialDefense), int32(10)), ""
        );

        // Count StatBoost effects
        (EffectInstance[] memory effectsOrig,) = engineOriginal.getEffects(battleKeyOrig, 0, 0);
        (EffectInstance[] memory effectsKV,) = engineKV.getEffects(battleKeyKV, 0, 0);

        uint256 statBoostCountOrig = 0;
        uint256 statBoostCountKV = 0;

        for (uint256 i = 0; i < effectsOrig.length; i++) {
            if (keccak256(abi.encodePacked(effectsOrig[i].effect.name())) == keccak256(abi.encodePacked("Stat Boost"))) {
                statBoostCountOrig++;
            }
        }
        for (uint256 i = 0; i < effectsKV.length; i++) {
            if (keccak256(abi.encodePacked(effectsKV[i].effect.name())) == keccak256(abi.encodePacked("Stat Boost"))) {
                statBoostCountKV++;
            }
        }

        console.log("Original StatBoost effects: %d", statBoostCountOrig);
        console.log("KV StatBoost effects:       %d", statBoostCountKV);
        console.log("Total effects (Original):   %d", effectsOrig.length);
        console.log("Total effects (KV):         %d", effectsKV.length);

        // KV should only have 1 StatBoost effect
        assertEq(statBoostCountKV, 1, "KV should have exactly 1 StatBoost effect");

        // Verify stats match
        assertEq(
            engineOriginal.getMonStateForBattle(battleKeyOrig, 0, 0, MonStateIndexName.Attack),
            engineKV.getMonStateForBattle(battleKeyKV, 0, 0, MonStateIndexName.Attack),
            "Attack should match"
        );
    }

    function test_gasComparison_fifthBoostFromSameSource() public {
        console.log("\n=== Fifth Boost (Same Source, More Iteration in Original) ===");

        // Original - setup and add 4 boosts
        bytes32 battleKeyOrig = _setupBattleOriginal();
        for (uint256 i = 0; i < 4; i++) {
            _commitRevealExecuteForAliceAndBob(
                engineOriginal, commitManagerOriginal, battleKeyOrig,
                0, NO_OP_MOVE_INDEX,
                abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
            );
        }

        // Original - fifth boost
        uint256 gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineOriginal, commitManagerOriginal, battleKeyOrig,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
        );
        uint256 gasOriginal = gasBefore - gasleft();

        // KV - setup and add 4 boosts
        bytes32 battleKeyKV = _setupBattleKV();
        for (uint256 i = 0; i < 4; i++) {
            _commitRevealExecuteForAliceAndBob(
                engineKV, commitManagerKV, battleKeyKV,
                0, NO_OP_MOVE_INDEX,
                abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
            );
        }

        // KV - fifth boost
        gasBefore = gasleft();
        _commitRevealExecuteForAliceAndBob(
            engineKV, commitManagerKV, battleKeyKV,
            0, NO_OP_MOVE_INDEX,
            abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(10)), ""
        );
        uint256 gasKV = gasBefore - gasleft();

        console.log("Original: %d gas", gasOriginal);
        console.log("KV:       %d gas", gasKV);
        console.log("Delta:    %s%d gas", gasKV > gasOriginal ? "+" : "-", gasKV > gasOriginal ? gasKV - gasOriginal : gasOriginal - gasKV);
    }
}
