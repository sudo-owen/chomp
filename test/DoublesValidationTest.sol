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

/**
 * @title DoublesValidationTest
 * @notice Tests for doubles battle validation boundary conditions
 * @dev Tests scenarios:
 *      - One player has 1 KO'd mon (with/without valid switch targets)
 *      - Both players have 1 KO'd mon each (various combinations)
 *      - Switch target validation (can't switch to other slot's active mon)
 *      - NO_OP allowed only when no valid switch targets
 */
contract DoublesValidationTest is Test {
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
    CustomAttack strongAttack;

    uint256 constant TIMEOUT_DURATION = 100;

    function setUp() public {
        engine = new Engine();
        typeCalc = new TestTypeCalculator();
        defaultOracle = new DefaultRandomnessOracle();
        // Use 3 mons per team to test switch target scenarios
        validator = new DefaultValidator(
            engine, DefaultValidator.Args({MONS_PER_TEAM: 3, MOVES_PER_MON: 4, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        matchmaker = new DefaultMatchmaker(engine);
        commitManager = new DoublesCommitManager(engine);
        defaultRegistry = new TestTeamRegistry();

        customAttack = new CustomAttack(
            engine, typeCalc, CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );
        strongAttack = new CustomAttack(
            engine, typeCalc, CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 200, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 0})
        );

        // Register teams for Alice and Bob (3 mons for doubles with switch options)
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = customAttack;
        moves[1] = customAttack;
        moves[2] = customAttack;
        moves[3] = customAttack;

        Mon[] memory team = new Mon[](3);
        team[0] = _createMon(100, 10, moves);  // Mon 0: 100 HP, speed 10
        team[1] = _createMon(100, 8, moves);   // Mon 1: 100 HP, speed 8
        team[2] = _createMon(100, 6, moves);   // Mon 2: 100 HP, speed 6 (reserve)

        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);

        // Authorize matchmaker
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

    function _createMon(uint32 hp, uint32 speed, IMoveSet[] memory moves) internal pure returns (Mon memory) {
        return Mon({
            stats: MonStats({
                hp: hp,
                stamina: 50,
                speed: speed,
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
    }

    function _startDoublesBattle() internal returns (bytes32 battleKey) {
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
            gameMode: GameMode.Doubles
        });

        vm.startPrank(ALICE);
        battleKey = matchmaker.proposeBattle(proposal);

        bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
        vm.startPrank(BOB);
        matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);

        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);
        vm.stopPrank();
    }

    function _doublesCommitRevealExecute(
        bytes32 battleKey,
        uint8 aliceMove0, uint240 aliceExtra0,
        uint8 aliceMove1, uint240 aliceExtra1,
        uint8 bobMove0, uint240 bobExtra0,
        uint8 bobMove1, uint240 bobExtra1
    ) internal {
        uint256 turnId = engine.getTurnIdForBattleState(battleKey);
        bytes32 aliceSalt = bytes32("alicesalt");
        bytes32 bobSalt = bytes32("bobsalt");

        if (turnId % 2 == 0) {
            bytes32 aliceHash = keccak256(abi.encodePacked(aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, aliceSalt));
            vm.startPrank(ALICE);
            commitManager.commitMoves(battleKey, aliceHash);
            vm.stopPrank();

            vm.startPrank(BOB);
            commitManager.revealMoves(battleKey, bobMove0, bobExtra0, bobMove1, bobExtra1, bobSalt, false);
            vm.stopPrank();

            vm.startPrank(ALICE);
            commitManager.revealMoves(battleKey, aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, aliceSalt, false);
            vm.stopPrank();
        } else {
            bytes32 bobHash = keccak256(abi.encodePacked(bobMove0, bobExtra0, bobMove1, bobExtra1, bobSalt));
            vm.startPrank(BOB);
            commitManager.commitMoves(battleKey, bobHash);
            vm.stopPrank();

            vm.startPrank(ALICE);
            commitManager.revealMoves(battleKey, aliceMove0, aliceExtra0, aliceMove1, aliceExtra1, aliceSalt, false);
            vm.stopPrank();

            vm.startPrank(BOB);
            commitManager.revealMoves(battleKey, bobMove0, bobExtra0, bobMove1, bobExtra1, bobSalt, false);
            vm.stopPrank();
        }

        engine.execute(battleKey);
    }

    function _doInitialSwitch(bytes32 battleKey) internal {
        _doublesCommitRevealExecute(
            battleKey,
            SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1,
            SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1
        );
    }

    // =========================================
    // Direct Validator Tests
    // =========================================

    /**
     * @notice Test that on turn 0, only SWITCH_MOVE_INDEX is valid for all slots
     */
    function test_turn0_onlySwitchAllowed() public {
        bytes32 battleKey = _startDoublesBattle();

        // Turn 0: validatePlayerMoveForSlot should only accept SWITCH_MOVE_INDEX
        // Test slot 0
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 0), "SWITCH should be valid on turn 0");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Attack should be invalid on turn 0");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "NO_OP should be invalid on turn 0 (valid targets exist)");

        // Test slot 1
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 1, 1), "SWITCH should be valid on turn 0 slot 1");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Attack should be invalid on turn 0 slot 1");
    }

    /**
     * @notice Test that after initial switch, attacks are valid for non-KO'd mons
     */
    function test_afterTurn0_attacksAllowed() public {
        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Attacks should be valid
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Attack should be valid after turn 0");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Attack should be valid for slot 1");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "NO_OP should be valid");

        // Switch should also still be valid (to mon index 2, the reserve)
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 2), "Switch to reserve should be valid");
    }

    /**
     * @notice Test that switch to same mon is invalid (except turn 0)
     */
    function test_switchToSameMonInvalid() public {
        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Trying to switch slot 0 (which has mon 0) to mon 0 should fail
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 0), "Switch to same mon should be invalid");

        // Trying to switch slot 1 (which has mon 1) to mon 1 should fail
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 1, 1), "Switch to same mon should be invalid for slot 1");
    }

    /**
     * @notice Test that switch to mon active in other slot is invalid
     */
    function test_switchToOtherSlotActiveMonInvalid() public {
        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // After initial switch: slot 0 has mon 0, slot 1 has mon 1
        // Trying to switch slot 0 to mon 1 (active in slot 1) should fail
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 1), "Switch to other slot's active mon should be invalid");

        // Trying to switch slot 1 to mon 0 (active in slot 0) should fail
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 1, 0), "Switch to other slot's active mon should be invalid");

        // But switch to reserve mon (index 2) should be valid
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 2), "Switch to reserve should be valid");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 1, 2), "Switch to reserve from slot 1 should be valid");
    }

    // =========================================
    // One Player Has 1 KO'd Mon Tests
    // =========================================

    /**
     * @notice Setup: Alice's slot 0 mon is KO'd, but she has a reserve mon to switch to
     *         Expected: Alice must switch slot 0, can use any move for slot 1
     */
    function test_onePlayerOneKO_withValidTarget() public {
        // Create teams where Alice's mon 0 has very low HP
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        Mon[] memory aliceTeam = new Mon[](3);
        aliceTeam[0] = _createMon(1, 10, moves);   // Will be KO'd easily
        aliceTeam[1] = _createMon(100, 8, moves);
        aliceTeam[2] = _createMon(100, 6, moves);  // Reserve

        Mon[] memory bobTeam = new Mon[](3);
        bobTeam[0] = _createMon(100, 20, moves);   // Faster to attack first
        bobTeam[1] = _createMon(100, 18, moves);
        bobTeam[2] = _createMon(100, 16, moves);

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Bob attacks Alice's slot 0, KO'ing it
        _doublesCommitRevealExecute(
            battleKey,
            0, 0, NO_OP_MOVE_INDEX, 0,  // Alice: slot 0 attacks, slot 1 no-op
            0, 0, NO_OP_MOVE_INDEX, 0   // Bob: slot 0 attacks (will KO Alice slot 0), slot 1 no-op
        );

        // Verify Alice's slot 0 mon is KO'd
        int32 isKO = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKO, 1, "Alice's mon 0 should be KO'd");

        // Now validate: Alice slot 0 must switch (to reserve mon 2)
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Attack should be invalid for KO'd slot");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "NO_OP should be invalid when valid switch exists");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 2), "Switch to reserve should be valid");

        // Alice slot 1 can use any move (not KO'd)
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Attack should be valid for non-KO'd slot");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 1, 0), "NO_OP should be valid for non-KO'd slot");

        // Bob's slots should be able to use any move
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 0, 0), "Bob slot 0 attack should be valid");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 1, 0), "Bob slot 1 attack should be valid");
    }

    /**
     * @notice Setup: Alice's slot 0 mon is KO'd, and her only other mon is in slot 1 (no reserve)
     *         Expected: Alice can use NO_OP for slot 0 since no valid switch target
     */
    function test_onePlayerOneKO_noValidTarget() public {
        // Use only 2 mons per team for this test
        DefaultValidator validator2Mon = new DefaultValidator(
            engine, DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 4, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        DoublesCommitManager commitManager2 = new DoublesCommitManager(engine);
        TestTeamRegistry registry2 = new TestTeamRegistry();

        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = _createMon(1, 10, moves);   // Will be KO'd
        aliceTeam[1] = _createMon(100, 8, moves);  // Active in slot 1

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = _createMon(100, 20, moves);
        bobTeam[1] = _createMon(100, 18, moves);

        registry2.setTeam(ALICE, aliceTeam);
        registry2.setTeam(BOB, bobTeam);

        // Start battle with 2-mon validator
        bytes32 salt = "";
        uint96 p0TeamIndex = 0;
        uint256[] memory p0TeamIndices = registry2.getMonRegistryIndicesForTeam(ALICE, p0TeamIndex);
        bytes32 p0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));

        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: p0TeamHash,
            p1: BOB,
            p1TeamIndex: 0,
            teamRegistry: registry2,
            validator: validator2Mon,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            engineHooks: new IEngineHook[](0),
            moveManager: address(commitManager2),
            matchmaker: matchmaker,
            gameMode: GameMode.Doubles
        });

        vm.startPrank(ALICE);
        bytes32 battleKey = matchmaker.proposeBattle(proposal);
        bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
        vm.startPrank(BOB);
        matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        // Turn 0: Initial switch
        {
            uint256 turnId = engine.getTurnIdForBattleState(battleKey);
            bytes32 aliceSalt = bytes32("alicesalt");
            bytes32 bobSalt = bytes32("bobsalt");
            bytes32 aliceHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, uint240(0), SWITCH_MOVE_INDEX, uint240(1), aliceSalt));
            vm.startPrank(ALICE);
            commitManager2.commitMoves(battleKey, aliceHash);
            vm.stopPrank();
            vm.startPrank(BOB);
            commitManager2.revealMoves(battleKey, SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1, bobSalt, false);
            vm.stopPrank();
            vm.startPrank(ALICE);
            commitManager2.revealMoves(battleKey, SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1, aliceSalt, false);
            vm.stopPrank();
            engine.execute(battleKey);
        }

        // Turn 1: Bob KOs Alice's slot 0
        {
            bytes32 aliceSalt = bytes32("alicesalt2");
            bytes32 bobSalt = bytes32("bobsalt2");
            bytes32 bobHash = keccak256(abi.encodePacked(uint8(0), uint240(0), uint8(NO_OP_MOVE_INDEX), uint240(0), bobSalt));
            vm.startPrank(BOB);
            commitManager2.commitMoves(battleKey, bobHash);
            vm.stopPrank();
            vm.startPrank(ALICE);
            commitManager2.revealMoves(battleKey, uint8(0), 0, uint8(NO_OP_MOVE_INDEX), 0, aliceSalt, false);
            vm.stopPrank();
            vm.startPrank(BOB);
            commitManager2.revealMoves(battleKey, uint8(0), 0, uint8(NO_OP_MOVE_INDEX), 0, bobSalt, false);
            vm.stopPrank();
            engine.execute(battleKey);
        }

        // Verify Alice's mon 0 is KO'd
        int32 isKO = engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut);
        assertEq(isKO, 1, "Alice's mon 0 should be KO'd");

        // Now Alice's slot 0 is KO'd, and slot 1 has mon 1
        // There's no valid switch target (mon 0 is KO'd, mon 1 is in other slot)
        // Therefore NO_OP should be valid
        assertTrue(validator2Mon.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "NO_OP should be valid when no switch targets");
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Attack should be invalid for KO'd slot");
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 1), "Can't switch to other slot's mon");
    }

    // =========================================
    // Both Players Have 1 KO'd Mon Tests
    // =========================================

    /**
     * @notice Setup: Both Alice and Bob have their slot 0 mons KO'd, both have reserves
     *         Expected: Both must switch their slot 0
     */
    function test_bothPlayersOneKO_bothHaveValidTargets() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        // Both teams have weak slot 0 mons, and fast slot 1 mons that will KO opponent's slot 0
        Mon[] memory aliceTeam = new Mon[](3);
        aliceTeam[0] = _createMon(1, 5, moves);     // Weak, slow - will be KO'd
        aliceTeam[1] = _createMon(100, 20, moves);  // Fast - attacks first
        aliceTeam[2] = _createMon(100, 6, moves);   // Reserve

        Mon[] memory bobTeam = new Mon[](3);
        bobTeam[0] = _createMon(1, 5, moves);       // Weak, slow - will be KO'd
        bobTeam[1] = _createMon(100, 18, moves);    // Fast - attacks second
        bobTeam[2] = _createMon(100, 6, moves);     // Reserve

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Slot 1 mons attack opponent's slot 0 (default targeting), KO'ing both slot 0s
        // Order: Alice slot 1 (speed 20) → Bob slot 1 (speed 18) → both slot 0s too slow to matter
        _doublesCommitRevealExecute(
            battleKey,
            NO_OP_MOVE_INDEX, 0, 0, 0,  // Alice: slot 0 no-op, slot 1 attacks
            NO_OP_MOVE_INDEX, 0, 0, 0   // Bob: slot 0 no-op, slot 1 attacks
        );

        // Verify both slot 0 mons are KO'd
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice mon 0 KO'd");
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.IsKnockedOut), 1, "Bob mon 0 KO'd");

        // Both must switch slot 0 to reserve (mon 2)
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 2), "Alice must switch to reserve");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 1, 0, 2), "Bob must switch to reserve");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Alice attack invalid");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 0, 0), "Bob attack invalid");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "Alice NO_OP invalid (has target)");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 1, 0, 0), "Bob NO_OP invalid (has target)");

        // Slot 1 for both can use any move
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Alice slot 1 attack valid");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 1, 0), "Bob slot 1 attack valid");
    }

    /**
     * @notice Setup: Both players have slot 0 KO'd, only 2 mons per team (no reserve)
     *         Expected: Both can use NO_OP for slot 0
     */
    function test_bothPlayersOneKO_neitherHasValidTarget() public {
        // Use 2-mon teams
        DefaultValidator validator2Mon = new DefaultValidator(
            engine, DefaultValidator.Args({MONS_PER_TEAM: 2, MOVES_PER_MON: 4, TIMEOUT_DURATION: TIMEOUT_DURATION})
        );
        DoublesCommitManager commitManager2 = new DoublesCommitManager(engine);
        TestTeamRegistry registry2 = new TestTeamRegistry();

        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        // Both teams: weak slot 0, fast slot 1 that will KO opponent's slot 0
        Mon[] memory aliceTeam = new Mon[](2);
        aliceTeam[0] = _createMon(1, 5, moves);     // Will be KO'd
        aliceTeam[1] = _createMon(100, 20, moves);  // Fast, attacks first

        Mon[] memory bobTeam = new Mon[](2);
        bobTeam[0] = _createMon(1, 5, moves);       // Will be KO'd
        bobTeam[1] = _createMon(100, 18, moves);    // Fast, attacks second

        registry2.setTeam(ALICE, aliceTeam);
        registry2.setTeam(BOB, bobTeam);

        // Start battle
        bytes32 salt = "";
        uint96 p0TeamIndex = 0;
        uint256[] memory p0TeamIndices = registry2.getMonRegistryIndicesForTeam(ALICE, p0TeamIndex);
        bytes32 p0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));

        ProposedBattle memory proposal = ProposedBattle({
            p0: ALICE,
            p0TeamIndex: 0,
            p0TeamHash: p0TeamHash,
            p1: BOB,
            p1TeamIndex: 0,
            teamRegistry: registry2,
            validator: validator2Mon,
            rngOracle: defaultOracle,
            ruleset: IRuleset(address(0)),
            engineHooks: new IEngineHook[](0),
            moveManager: address(commitManager2),
            matchmaker: matchmaker,
            gameMode: GameMode.Doubles
        });

        vm.startPrank(ALICE);
        bytes32 battleKey = matchmaker.proposeBattle(proposal);
        bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
        vm.startPrank(BOB);
        matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);
        vm.startPrank(ALICE);
        matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        // Turn 0: Initial switch
        {
            bytes32 aliceSalt = bytes32("as");
            bytes32 bobSalt = bytes32("bs");
            bytes32 aliceHash = keccak256(abi.encodePacked(SWITCH_MOVE_INDEX, uint240(0), SWITCH_MOVE_INDEX, uint240(1), aliceSalt));
            vm.startPrank(ALICE);
            commitManager2.commitMoves(battleKey, aliceHash);
            vm.stopPrank();
            vm.startPrank(BOB);
            commitManager2.revealMoves(battleKey, SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1, bobSalt, false);
            vm.stopPrank();
            vm.startPrank(ALICE);
            commitManager2.revealMoves(battleKey, SWITCH_MOVE_INDEX, 0, SWITCH_MOVE_INDEX, 1, aliceSalt, false);
            vm.stopPrank();
            engine.execute(battleKey);
        }

        // Turn 1: Both slot 1 mons attack opponent's slot 0, KO'ing both
        {
            bytes32 aliceSalt = bytes32("as2");
            bytes32 bobSalt = bytes32("bs2");
            bytes32 bobHash = keccak256(abi.encodePacked(uint8(NO_OP_MOVE_INDEX), uint240(0), uint8(0), uint240(0), bobSalt));
            vm.startPrank(BOB);
            commitManager2.commitMoves(battleKey, bobHash);
            vm.stopPrank();
            vm.startPrank(ALICE);
            commitManager2.revealMoves(battleKey, uint8(NO_OP_MOVE_INDEX), 0, uint8(0), 0, aliceSalt, false);
            vm.stopPrank();
            vm.startPrank(BOB);
            commitManager2.revealMoves(battleKey, uint8(NO_OP_MOVE_INDEX), 0, uint8(0), 0, bobSalt, false);
            vm.stopPrank();
            engine.execute(battleKey);
        }

        // Verify both slot 0 mons KO'd
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice mon 0 KO'd");
        assertEq(engine.getMonStateForBattle(battleKey, 1, 0, MonStateIndexName.IsKnockedOut), 1, "Bob mon 0 KO'd");

        // Both should be able to NO_OP slot 0 (no valid switch targets)
        assertTrue(validator2Mon.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "Alice NO_OP valid");
        assertTrue(validator2Mon.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 1, 0, 0), "Bob NO_OP valid");

        // Attacks still invalid for KO'd slot
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Alice attack invalid");
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, 0, 1, 0, 0), "Bob attack invalid");

        // Can't switch to other slot's mon
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 1), "Alice can't switch to slot 1 mon");
        assertFalse(validator2Mon.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 1, 0, 1), "Bob can't switch to slot 1 mon");

        // Slot 1 can still attack
        assertTrue(validator2Mon.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Alice slot 1 attack valid");
        assertTrue(validator2Mon.validatePlayerMoveForSlot(battleKey, 0, 1, 1, 0), "Bob slot 1 attack valid");
    }

    // =========================================
    // Integration Test: Full Flow with KO and Forced Switch
    // =========================================

    /**
     * @notice Full integration test: Verify validation rejects attack for KO'd slot with valid targets
     *         And accepts switch to reserve
     */
    function test_fullFlow_KOAndForcedSwitch() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        Mon[] memory aliceTeam = new Mon[](3);
        aliceTeam[0] = _createMon(1, 5, moves);     // Will be KO'd (slow)
        aliceTeam[1] = _createMon(100, 8, moves);
        aliceTeam[2] = _createMon(100, 6, moves);   // Reserve

        Mon[] memory bobTeam = new Mon[](3);
        bobTeam[0] = _createMon(100, 20, moves);    // Fast - attacks first
        bobTeam[1] = _createMon(100, 18, moves);
        bobTeam[2] = _createMon(100, 16, moves);

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);

        // Turn 0: Initial switch
        _doInitialSwitch(battleKey);
        assertEq(engine.getTurnIdForBattleState(battleKey), 1);

        // Turn 1: Bob KOs Alice's slot 0
        _doublesCommitRevealExecute(
            battleKey,
            NO_OP_MOVE_INDEX, 0, NO_OP_MOVE_INDEX, 0,  // Alice: both no-op
            0, 0, NO_OP_MOVE_INDEX, 0                   // Bob: slot 0 attacks Alice's slot 0
        );

        // Verify turn advanced and mon is KO'd
        assertEq(engine.getTurnIdForBattleState(battleKey), 2);
        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice mon 0 KO'd");

        // Verify validation state after KO:
        // - Alice slot 0: must switch (attack invalid, NO_OP invalid since reserve exists)
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 0, 0), "Attack invalid for KO'd slot");
        assertFalse(validator.validatePlayerMoveForSlot(battleKey, NO_OP_MOVE_INDEX, 0, 0, 0), "NO_OP invalid (reserve exists)");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, SWITCH_MOVE_INDEX, 0, 0, 2), "Switch to reserve valid");

        // - Alice slot 1: can use any move
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 0, 1, 0), "Alice slot 1 attack valid");

        // - Bob: both slots can use any move
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 0, 0), "Bob slot 0 attack valid");
        assertTrue(validator.validatePlayerMoveForSlot(battleKey, 0, 1, 1, 0), "Bob slot 1 attack valid");

        // Game should still be ongoing
        assertEq(engine.getWinner(battleKey), address(0));
    }

    /**
     * @notice Test that reveal fails when trying to use attack for KO'd slot with valid targets
     * @dev After KO with valid switch target, it's a single-player switch turn (Alice only)
     */
    function test_revealFailsForInvalidMoveOnKOdSlot() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        Mon[] memory aliceTeam = new Mon[](3);
        aliceTeam[0] = _createMon(1, 5, moves);     // Slow, will be KO'd
        aliceTeam[1] = _createMon(100, 8, moves);
        aliceTeam[2] = _createMon(100, 6, moves);   // Reserve

        Mon[] memory bobTeam = new Mon[](3);
        bobTeam[0] = _createMon(100, 20, moves);    // Fast, attacks first
        bobTeam[1] = _createMon(100, 18, moves);
        bobTeam[2] = _createMon(100, 16, moves);

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Bob KOs Alice's slot 0
        _doublesCommitRevealExecute(
            battleKey,
            NO_OP_MOVE_INDEX, 0, NO_OP_MOVE_INDEX, 0,  // Alice: both no-op
            0, 0, NO_OP_MOVE_INDEX, 0                   // Bob: slot 0 attacks
        );

        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice mon 0 KO'd");

        // Verify it's a single-player switch turn (playerSwitchForTurnFlag = 0 for Alice only)
        BattleContext memory ctx = engine.getBattleContext(battleKey);
        assertEq(ctx.playerSwitchForTurnFlag, 0, "Should be Alice-only switch turn");

        // Turn 2: Single-player switch turn - only Alice acts (no commits needed)
        // Alice tries to reveal with attack for KO'd slot 0 - should fail with InvalidMove
        bytes32 aliceSalt = bytes32("alicesalt");

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(DoublesCommitManager.InvalidMove.selector, ALICE, 0));
        commitManager.revealMoves(battleKey, uint8(0), 0, uint8(NO_OP_MOVE_INDEX), 0, aliceSalt, false);
        vm.stopPrank();
    }

    /**
     * @notice Test single-player switch turn: only the player with KO'd mon acts
     */
    function test_singlePlayerSwitchTurn() public {
        IMoveSet[] memory moves = new IMoveSet[](4);
        moves[0] = strongAttack;
        moves[1] = strongAttack;
        moves[2] = strongAttack;
        moves[3] = strongAttack;

        Mon[] memory aliceTeam = new Mon[](3);
        aliceTeam[0] = _createMon(1, 5, moves);     // Slow, will be KO'd
        aliceTeam[1] = _createMon(100, 8, moves);
        aliceTeam[2] = _createMon(100, 6, moves);   // Reserve

        Mon[] memory bobTeam = new Mon[](3);
        bobTeam[0] = _createMon(100, 20, moves);    // Fast
        bobTeam[1] = _createMon(100, 18, moves);
        bobTeam[2] = _createMon(100, 16, moves);

        defaultRegistry.setTeam(ALICE, aliceTeam);
        defaultRegistry.setTeam(BOB, bobTeam);

        bytes32 battleKey = _startDoublesBattle();
        vm.warp(block.timestamp + 1);
        _doInitialSwitch(battleKey);

        // Turn 1: Bob KOs Alice's slot 0
        _doublesCommitRevealExecute(
            battleKey,
            NO_OP_MOVE_INDEX, 0, NO_OP_MOVE_INDEX, 0,
            0, 0, NO_OP_MOVE_INDEX, 0
        );

        assertEq(engine.getMonStateForBattle(battleKey, 0, 0, MonStateIndexName.IsKnockedOut), 1, "Alice mon 0 KO'd");

        // Verify it's a single-player switch turn
        BattleContext memory ctx = engine.getBattleContext(battleKey);
        assertEq(ctx.playerSwitchForTurnFlag, 0, "Should be Alice-only switch turn");

        // Bob should NOT be able to commit (it's not his turn)
        vm.startPrank(BOB);
        bytes32 bobHash = keccak256(abi.encodePacked(uint8(0), uint240(0), uint8(0), uint240(0), bytes32("bobsalt")));
        vm.expectRevert(DoublesCommitManager.PlayerNotAllowed.selector);
        commitManager.commitMoves(battleKey, bobHash);
        vm.stopPrank();

        // Alice reveals her switch (no commit needed for single-player turns)
        bytes32 aliceSalt = bytes32("alicesalt");
        vm.startPrank(ALICE);
        commitManager.revealMoves(battleKey, SWITCH_MOVE_INDEX, 2, NO_OP_MOVE_INDEX, 0, aliceSalt, true);
        vm.stopPrank();

        // Verify switch happened and turn advanced
        assertEq(engine.getActiveMonIndexForSlot(battleKey, 0, 0), 2, "Alice slot 0 should now have mon 2");
        assertEq(engine.getTurnIdForBattleState(battleKey), 3);

        // Next turn should be normal (both players act)
        ctx = engine.getBattleContext(battleKey);
        assertEq(ctx.playerSwitchForTurnFlag, 2, "Should be normal turn now");
    }
}
