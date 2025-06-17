// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Structs.sol";

import {Engine} from "../../src/Engine.sol";
import {FastCommitManager} from "../../src/FastCommitManager.sol";
import {IValidator} from "../../src/IValidator.sol";
import {IRandomnessOracle} from "../../src/rng/IRandomnessOracle.sol";
import {ITeamRegistry} from "../../src/teams/ITeamRegistry.sol";
import {IEngineHook} from "../../src/IEngineHook.sol";

import {Test} from "forge-std/Test.sol";

abstract contract BattleHelper is Test {
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);

    // Helper function to commit, reveal, and execute moves for both players
    function _commitRevealExecuteForAliceAndBob(
        Engine engine,
        FastCommitManager commitManager,
        bytes32 battleKey,
        uint256 aliceMoveIndex,
        uint256 bobMoveIndex,
        bytes memory aliceExtraData,
        bytes memory bobExtraData
    ) internal {
        bytes32 salt = "";
        bytes32 aliceMoveHash = keccak256(abi.encodePacked(aliceMoveIndex, salt, aliceExtraData));
        bytes32 bobMoveHash = keccak256(abi.encodePacked(bobMoveIndex, salt, bobExtraData));
        // Decide which player commits
        uint256 turnId = engine.getTurnIdForBattleState(battleKey);
        if (turnId % 2 == 0) {
            vm.startPrank(ALICE);
            commitManager.commitMove(battleKey, aliceMoveHash);
            vm.startPrank(BOB);
            commitManager.revealMove(battleKey, bobMoveIndex, salt, bobExtraData, true);
            vm.startPrank(ALICE);
            commitManager.revealMove(battleKey, aliceMoveIndex, salt, aliceExtraData, true);
        } else {
            vm.startPrank(BOB);
            commitManager.commitMove(battleKey, bobMoveHash);
            vm.startPrank(ALICE);
            commitManager.revealMove(battleKey, aliceMoveIndex, salt, aliceExtraData, true);
            vm.startPrank(BOB);
            commitManager.revealMove(battleKey, bobMoveIndex, salt, bobExtraData, true);
        }
    }

    function _startBattle(
        IValidator validator,
        Engine engine,
        IRandomnessOracle rngOracle,
        ITeamRegistry defaultRegistry
    ) internal returns (bytes32) {
        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: rngOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            engineHook: IEngineHook(address(0))
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.startPrank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.startPrank(ALICE);
        engine.startBattle(battleKey, "", 0);
        return battleKey;
    }

    function _startBattle(
        IValidator validator,
        Engine engine,
        IRandomnessOracle rngOracle,
        ITeamRegistry defaultRegistry,
        IEngineHook engineHook
    ) internal returns (bytes32) {
        // Start a battle
        StartBattleArgs memory args = StartBattleArgs({
            p0: ALICE,
            p1: BOB,
            validator: validator,
            rngOracle: rngOracle,
            ruleset: IRuleset(address(0)),
            teamRegistry: defaultRegistry,
            p0TeamHash: keccak256(
                abi.encodePacked(bytes32(""), uint256(0), defaultRegistry.getMonRegistryIndicesForTeam(ALICE, 0))
            ),
            engineHook: engineHook
        });
        vm.startPrank(ALICE);
        bytes32 battleKey = engine.proposeBattle(args);
        bytes32 battleIntegrityHash = keccak256(
            abi.encodePacked(args.validator, args.rngOracle, args.ruleset, args.teamRegistry, args.p0TeamHash)
        );
        vm.startPrank(BOB);
        engine.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.startPrank(ALICE);
        engine.startBattle(battleKey, "", 0);
        return battleKey;
    }
}
