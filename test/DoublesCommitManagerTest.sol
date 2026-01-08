// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {DoublesCommitManager} from "../src/DoublesCommitManager.sol";
import {Engine} from "../src/Engine.sol";
import {DefaultValidator} from "../src/DefaultValidator.sol";
import {IEngineHook} from "../src/IEngineHook.sol";
import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";
import {TestTypeCalculator} from "./mocks/TestTypeCalculator.sol";
import {CustomAttack} from "./mocks/CustomAttack.sol";

contract DoublesCommitManagerTest is Test {
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);

    DoublesCommitManager commitManager;
    Engine engine;
    DefaultValidator validator;
    ITypeCalculator typeCalc;
    DefaultRandomnessOracle defaultOracle;
    DefaultMatchmaker matchmaker;
    TestTeamRegistry defaultRegistry;
    CustomAttack customAttack;

    uint256 constant TIMEOUT_DURATION = 100;

    function setUp() public {
        // Deploy core contracts
        engine = new Engine();
        typeCalc = new TestTypeCalculator();
        defaultOracle = new DefaultRandomnessOracle();
        validator = new DefaultValidator(
            engine, DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 4, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        matchmaker = new DefaultMatchmaker(engine);
        commitManager = new DoublesCommitManager(engine);
        defaultRegistry = new TestTeamRegistry();

        // Create a simple attack for testing
        customAttack = new CustomAttack(
            engine, typeCalc, CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );

        // Register teams for Alice and Bob (need at least 2 mons for doubles)
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = customAttack;
        moves[1] = customAttack;
        moves[2] = customAttack;
        moves[3] = customAttack;

        Mon[] memory team = new Mon[](2);
        team[0] = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 50,
                speed: 10,
                attack: 10,
                defense: 10,
                specialAttack: 10,
                specialDefense: 10,
                type1: Type.Fire,
                type2: Type.None
            }),
            ability: IAbility(address(0)),
            moves: moves
        });
        team[1] = Mon({
            stats: MonStats({
                hp: 100,
                stamina: 50,
                speed: 8,
                attack: 10,
                defense: 10,
                specialAttack: 10,
                specialDefense: 10,
                type1: Type.Liquid,
                type2: Type.None
            }),
            ability: IAbility(address(0)),
            moves: moves
        });

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        // Authorize matchmaker for both players
        vm.startPrank(ALICE);
        address[] memory makersToAdd = new address[](1);
        makersToAdd[0] = address(matchmaker);
        address[] memory makersToRemove = new address[](0);
        engine.updateMatchmakers(makersToAdd, makersToRemove);
        vm.stopPrank();

        vm.startPrank(BOB);
        engine.updateMatchmakers(makersToAdd, makersToRemove);
        vm.stopPrank();
    }

    function _startDoublesBattle() internal returns (bytes32 battleKey) {
        // Compute p0 team hash
        bytes32 salt = "";
        uint96 p0TeamIndex = 0;
        uint256[] memory p0TeamIndices = defaultRegistry.getMonRegistryIndicesForTeam(ALICE, p0TeamIndex);
        bytes32 p0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));

        // Create proposal for DOUBLES
        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: p0TeamHash,
            p1: BOB,
            p1TeamIndex: 0,
            teamRegistry: defaultRegistry,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            engineHooks: new IEngineHook[](0),
            moveManager: address(commitManager),
            matchmaker: matchmaker,
            gameMode: GameMode.Doubles  // KEY: This is a doubles battle
        });

        // Propose battle
        vm.startPrank(ALICE);
        battleKey = matchmaker.proposeBattle(proposal);

        // Accept battle
        bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
        vm.startPrank(BOB);
        matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);

        // Confirm and start battle
        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);

        vm.stopPrank();
    }

    function test_doublesCommitAndReveal() public {
        bytes32 battleKey = _startDoublesBattle();

        // Verify it's a doubles battle
        assertEq(uint256(engine.getGameMode(battleKey)), uint256(GameMode.Doubles));

        // Turn 0: Both players must switch to select initial active mons
        // Alice commits (even turn = p0 commits)
        bytes32 salt = bytes32("secret");
        uint8 aliceMove0 = SWITCH_MOVE_INDEX; // Switch to mon index 0 for slot 0
        uint240 aliceExtra0 = 0; // Mon index 0
        uint8 aliceMove1 = SWITCH_MOVE_INDEX; // Switch to mon index 1 for slot 1
        uint240 aliceExtra1 = 1; // Mon index 1

        bytes32 aliceHash = keccak256(abi.encodePacked(aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, salt));

        vm.startPrank(ALICE);
        commitManager.commitMoves(battleKey, aliceHash);
        vm.stopPrank();

        // Bob reveals first (non-committing player reveals first)
        uint8 bobMove0 = SWITCH_MOVE_INDEX;
        uint240 bobExtra0 = 0; // Mon index 0
        uint8 bobMove1 = SWITCH_MOVE_INDEX;
        uint240 bobExtra1 = 1; // Mon index 1
        bytes32 bobSalt = bytes32("bobsalt");

        vm.startPrank(BOB);
        commitManager.revealMoves(battleKey, bobMove0, bobExtra0, bobMove1, bobExtra1, bobSalt, false);
        vm.stopPrank();

        // Alice reveals (committing player reveals second)
        vm.startPrank(ALICE);
        commitManager.revealMoves(battleKey, aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, salt, false);
        vm.stopPrank();

        // Verify moves were set correctly
        MoveDecision memory p0Move = engine.getMoveDecisionForBattleState(battleKey, 0);
        MoveDecision memory p1Move = engine.getMoveDecisionForBattleState(battleKey, 1);

        // Check that moves were set (packedMoveIndex should have IS_REAL_TURN_BIT set)
        assertTrue(p0Move.packedMoveIndex & IS_REAL_TURN_BIT != 0, "Alice slot 0 move should be set");
        assertTrue(p1Move.packedMoveIndex & IS_REAL_TURN_BIT != 0, "Bob slot 0 move should be set");
    }

    function test_doublesCannotCommitToSinglesBattle() public {
        // Start a SINGLES battle instead
        bytes32 salt = "";
        uint96 p0TeamIndex = 0;
        uint256[] memory p0TeamIndices = defaultRegistry.getMonRegistryIndicesForTeam(ALICE, p0TeamIndex);
        bytes32 p0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));

        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: p0TeamHash,
            p1: BOB,
            p1TeamIndex: 0,
            teamRegistry: defaultRegistry,
            validator: validator,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            engineHooks: new IEngineHook[](0),
            moveManager: address(commitManager),
            matchmaker: matchmaker,
            gameMode: GameMode.Singles  // Singles battle
        });

        vm.startPrank(ALICE);
        bytes32 battleKey = matchmaker.proposeBattle(proposal);

        bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
        vm.startPrank(BOB);
        matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);

        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);

        // Try to commit with DoublesCommitManager - should fail
        bytes32 moveHash = keccak256(abi.encodePacked(uint8(0), uint240(0), uint8(0), uint240(0), bytes32("salt")));
        vm.expectRevert(DoublesCommitManager.NotDoublesMode.selector);
        commitManager.commitMoves(battleKey, moveHash);
        vm.stopPrank();
    }

    function test_doublesExecutionWithAllFourMoves() public {
        bytes32 battleKey = _startDoublesBattle();

        // Turn 0: Both players must switch to select initial active mons
        bytes32 salt = bytes32("secret");
        uint8 aliceMove0 = SWITCH_MOVE_INDEX;
        uint240 aliceExtra0 = 0; // Mon index 0 for slot 0
        uint8 aliceMove1 = SWITCH_MOVE_INDEX;
        uint240 aliceExtra1 = 1; // Mon index 1 for slot 1

        bytes32 aliceHash = keccak256(abi.encodePacked(aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, salt));

        vm.startPrank(ALICE);
        commitManager.commitMoves(battleKey, aliceHash);
        vm.stopPrank();

        // Bob reveals first
        uint8 bobMove0 = SWITCH_MOVE_INDEX;
        uint240 bobExtra0 = 0;
        uint8 bobMove1 = SWITCH_MOVE_INDEX;
        uint240 bobExtra1 = 1;
        bytes32 bobSalt = bytes32("bobsalt");

        vm.startPrank(BOB);
        commitManager.revealMoves(battleKey, bobMove0, bobExtra0, bobMove1, bobExtra1, bobSalt, false);
        vm.stopPrank();

        // Alice reveals
        vm.startPrank(ALICE);
        commitManager.revealMoves(battleKey, aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, salt, false);
        vm.stopPrank();

        // Execute turn 0 (initial mon selection)
        engine.execute(battleKey);

        // Verify the game advanced to turn 1
        assertEq(engine.getTurnIdForBattleState(battleKey), 1);

        // Verify active mon indices are set correctly for doubles
        assertEq(engine.getActiveMonIndexForSlot(battleKey, 0, 0), 0); // p0 slot 0 = mon 0
        assertEq(engine.getActiveMonIndexForSlot(battleKey, 0, 1), 1); // p0 slot 1 = mon 1
        assertEq(engine.getActiveMonIndexForSlot(battleKey, 1, 0), 0); // p1 slot 0 = mon 0
        assertEq(engine.getActiveMonIndexForSlot(battleKey, 1, 1), 1); // p1 slot 1 = mon 1

        // Turn 1: Both players use attack moves
        bytes32 salt2 = bytes32("secret2");
        uint8 aliceAttack0 = 0; // Move index 0 (attack)
        uint240 aliceTarget0 = 0; // Target opponent slot 0
        uint8 aliceAttack1 = 0;
        uint240 aliceTarget1 = 0;

        bytes32 aliceHash2 = keccak256(abi.encodePacked(aliceAttack0, aliceTarget0, aliceAttack1, aliceTarget1, salt2));

        vm.startPrank(BOB);
        // Bob commits this turn (odd turn = p1 commits)
        bytes32 bobSalt2 = bytes32("bobsalt2");
        uint8 bobAttack0 = 0;
        uint240 bobTarget0 = 0;
        uint8 bobAttack1 = 0;
        uint240 bobTarget1 = 0;
        bytes32 bobHash2 = keccak256(abi.encodePacked(bobAttack0, bobTarget0, bobAttack1, bobTarget1, bobSalt2));
        commitManager.commitMoves(battleKey, bobHash2);
        vm.stopPrank();

        // Alice reveals first (non-committing player)
        vm.startPrank(ALICE);
        commitManager.revealMoves(battleKey, aliceAttack0, aliceTarget0, aliceAttack1, aliceTarget1, salt2, false);
        vm.stopPrank();

        // Bob reveals
        vm.startPrank(BOB);
        commitManager.revealMoves(battleKey, bobAttack0, bobTarget0, bobAttack1, bobTarget1, bobSalt2, false);
        vm.stopPrank();

        // Execute turn 1 (attacks)
        engine.execute(battleKey);

        // Verify the game advanced to turn 2
        assertEq(engine.getTurnIdForBattleState(battleKey), 2);

        // Battle should still be ongoing (no winner yet)
        assertEq(engine.getWinner(battleKey), address(0));
    }

    function test_doublesWrongPreimageReverts() public {
        bytes32 battleKey = _startDoublesBattle();

        // Alice commits (turn 0 - must use SWITCH_MOVE_INDEX)
        bytes32 salt = bytes32("secret");
        uint8 aliceMove0 = SWITCH_MOVE_INDEX;
        uint240 aliceExtra0 = 0;
        uint8 aliceMove1 = SWITCH_MOVE_INDEX;
        uint240 aliceExtra1 = 1;

        bytes32 aliceHash = keccak256(abi.encodePacked(aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, salt));

        vm.startPrank(ALICE);
        commitManager.commitMoves(battleKey, aliceHash);
        vm.stopPrank();

        // Bob reveals first (also must use SWITCH_MOVE_INDEX on turn 0)
        vm.startPrank(BOB);
        commitManager.revealMoves(battleKey, SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1, bytes32("bobsalt"), false);
        vm.stopPrank();

        // Alice tries to reveal with wrong moves - should fail
        vm.startPrank(ALICE);
        vm.expectRevert(DoublesCommitManager.WrongPreimage.selector);
        commitManager.revealMoves(battleKey, SWITCH_MOVE_INDEX, 1, SWITCH_MOVE_INDEX, 0, salt, false); // Wrong extraData values
        vm.stopPrank();
    }
}
