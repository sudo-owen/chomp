// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Enums.sol";
import "./Structs.sol";

import {IEngine} from "./IEngine.sol";
import {IValidator} from "./IValidator.sol";

/**
 * @title DoublesCommitManager
 * @notice Commit/reveal manager for double battles where each player commits 2 moves per turn
 * @dev Follows same alternating commit scheme as DefaultCommitManager:
 *      - p0 commits on even turns, p1 commits on odd turns
 *      - Non-committing player reveals first, then committing player reveals
 *      - Each commit/reveal handles both slot 0 and slot 1 moves together
 */
contract DoublesCommitManager {
    IEngine private immutable ENGINE;

    // Player decision data - same structure as singles, but hash covers 2 moves
    mapping(bytes32 battleKey => mapping(uint256 playerIndex => PlayerDecisionData)) private playerData;

    error NotP0OrP1();
    error AlreadyCommited();
    error AlreadyRevealed();
    error NotYetRevealed();
    error RevealBeforeOtherCommit();
    error RevealBeforeSelfCommit();
    error WrongPreimage();
    error PlayerNotAllowed();
    error InvalidMove(address player, uint256 slotIndex);
    error BattleNotYetStarted();
    error BattleAlreadyComplete();
    error NotDoublesMode();

    event MoveCommit(bytes32 indexed battleKey, address player);
    event MoveReveal(bytes32 indexed battleKey, address player, uint256 moveIndex0, uint256 moveIndex1);

    constructor(IEngine engine) {
        ENGINE = engine;
    }

    /**
     * @notice Commit a hash of both moves for a doubles battle
     * @param battleKey The battle identifier
     * @param moveHash Hash of (moveIndex0, extraData0, moveIndex1, extraData1, salt)
     */
    function commitMoves(bytes32 battleKey, bytes32 moveHash) external {
        CommitContext memory ctx = ENGINE.getCommitContext(battleKey);

        // Validate battle state
        if (ctx.startTimestamp == 0) {
            revert BattleNotYetStarted();
        }
        if (ctx.gameMode != GameMode.Doubles) {
            revert NotDoublesMode();
        }

        address caller = msg.sender;
        uint256 playerIndex = (caller == ctx.p0) ? 0 : 1;

        if (caller != ctx.p0 && caller != ctx.p1) {
            revert NotP0OrP1();
        }

        if (ctx.winnerIndex != 2) {
            revert BattleAlreadyComplete();
        }

        PlayerDecisionData storage pd = playerData[battleKey][playerIndex];
        uint64 turnId = ctx.turnId;

        // Check no commitment exists for this turn
        if (turnId == 0) {
            if (pd.moveHash != bytes32(0)) {
                revert AlreadyCommited();
            }
        } else if (pd.lastCommitmentTurnId == turnId) {
            revert AlreadyCommited();
        }

        // Cannot commit if it's a single-player switch turn
        if (ctx.playerSwitchForTurnFlag != 2) {
            revert PlayerNotAllowed();
        }

        // Alternating commit: p0 on even turns, p1 on odd turns
        if (caller == ctx.p0 && turnId % 2 == 1) {
            revert PlayerNotAllowed();
        } else if (caller == ctx.p1 && turnId % 2 == 0) {
            revert PlayerNotAllowed();
        }

        // Store commitment
        pd.lastCommitmentTurnId = uint16(turnId);
        pd.moveHash = moveHash;
        pd.lastMoveTimestamp = uint96(block.timestamp);

        emit MoveCommit(battleKey, caller);
    }

    /**
     * @notice Reveal both moves for a doubles battle
     * @param battleKey The battle identifier
     * @param moveIndex0 Move index for slot 0 mon
     * @param extraData0 Extra data for slot 0 move (includes target)
     * @param moveIndex1 Move index for slot 1 mon
     * @param extraData1 Extra data for slot 1 move (includes target)
     * @param salt Salt used in the commitment hash
     * @param autoExecute Whether to auto-execute after both players reveal
     */
    function revealMoves(
        bytes32 battleKey,
        uint8 moveIndex0,
        uint240 extraData0,
        uint8 moveIndex1,
        uint240 extraData1,
        bytes32 salt,
        bool autoExecute
    ) external {
        CommitContext memory ctx = ENGINE.getCommitContext(battleKey);

        // Validate battle state
        if (ctx.startTimestamp == 0) {
            revert BattleNotYetStarted();
        }
        if (ctx.gameMode != GameMode.Doubles) {
            revert NotDoublesMode();
        }
        if (msg.sender != ctx.p0 && msg.sender != ctx.p1) {
            revert NotP0OrP1();
        }
        if (ctx.winnerIndex != 2) {
            revert BattleAlreadyComplete();
        }

        uint256 currentPlayerIndex = msg.sender == ctx.p0 ? 0 : 1;
        uint256 otherPlayerIndex = 1 - currentPlayerIndex;

        PlayerDecisionData storage currentPd = playerData[battleKey][currentPlayerIndex];
        PlayerDecisionData storage otherPd = playerData[battleKey][otherPlayerIndex];

        uint64 turnId = ctx.turnId;
        uint8 playerSwitchForTurnFlag = ctx.playerSwitchForTurnFlag;

        // Determine if player skips preimage check (same logic as singles)
        bool playerSkipsPreimageCheck;
        if (playerSwitchForTurnFlag == 2) {
            playerSkipsPreimageCheck =
                (((turnId % 2 == 1) && (currentPlayerIndex == 0)) || ((turnId % 2 == 0) && (currentPlayerIndex == 1)));
        } else {
            playerSkipsPreimageCheck = (playerSwitchForTurnFlag == currentPlayerIndex);
            if (!playerSkipsPreimageCheck) {
                revert PlayerNotAllowed();
            }
        }

        if (playerSkipsPreimageCheck) {
            // Must wait for other player's commitment
            if (playerSwitchForTurnFlag == 2) {
                if (turnId != 0) {
                    if (otherPd.lastCommitmentTurnId != turnId) {
                        revert RevealBeforeOtherCommit();
                    }
                } else {
                    if (otherPd.moveHash == bytes32(0)) {
                        revert RevealBeforeOtherCommit();
                    }
                }
            }
        } else {
            // Validate preimage for BOTH moves
            bytes32 expectedHash = keccak256(abi.encodePacked(moveIndex0, extraData0, moveIndex1, extraData1, salt));
            if (expectedHash != currentPd.moveHash) {
                revert WrongPreimage();
            }

            // Ensure reveal happens after caller commits
            if (currentPd.lastCommitmentTurnId != turnId) {
                revert RevealBeforeSelfCommit();
            }

            // Check that other player has already revealed
            if (otherPd.numMovesRevealed < turnId || otherPd.lastMoveTimestamp == 0) {
                revert NotYetRevealed();
            }
        }

        // Prevent double revealing
        if (currentPd.numMovesRevealed > turnId) {
            revert AlreadyRevealed();
        }

        // Validate both moves are legal for their respective slots
        IValidator validator = IValidator(ctx.validator);
        if (!validator.validatePlayerMoveForSlot(battleKey, moveIndex0, currentPlayerIndex, 0, extraData0)) {
            revert InvalidMove(msg.sender, 0);
        }
        if (!validator.validatePlayerMoveForSlot(battleKey, moveIndex1, currentPlayerIndex, 1, extraData1)) {
            revert InvalidMove(msg.sender, 1);
        }

        // Store both revealed moves
        // Slot 0 move uses standard setMove
        ENGINE.setMove(battleKey, currentPlayerIndex, moveIndex0, salt, extraData0);
        // Slot 1 move uses setMove with slot indicator (we'll add this to Engine)
        // For now, we encode slot 1 by using a different approach - store in p0Move2/p1Move2
        _setSlot1Move(battleKey, currentPlayerIndex, moveIndex1, salt, extraData1);

        currentPd.lastMoveTimestamp = uint96(block.timestamp);
        currentPd.numMovesRevealed += 1;

        // Handle single-player turns
        if (playerSwitchForTurnFlag == 0 || playerSwitchForTurnFlag == 1) {
            otherPd.lastMoveTimestamp = uint96(block.timestamp);
            otherPd.numMovesRevealed += 1;
        }

        emit MoveReveal(battleKey, msg.sender, moveIndex0, moveIndex1);

        // Auto execute if desired
        if (autoExecute) {
            if ((playerSwitchForTurnFlag == currentPlayerIndex) || (!playerSkipsPreimageCheck)) {
                ENGINE.execute(battleKey);
            }
        }
    }

    /**
     * @dev Internal function to set the slot 1 move
     * This calls ENGINE.setMove with a special encoding or we need to add a new Engine method
     * For now, we'll use a workaround - set slot 1 move through the engine
     */
    function _setSlot1Move(
        bytes32 battleKey,
        uint256 playerIndex,
        uint8 moveIndex,
        bytes32 salt,
        uint240 extraData
    ) internal {
        // We need Engine to have a setMoveForSlot function
        // For now, we'll call setMove with playerIndex + 2 to indicate slot 1
        // Engine will need to interpret this (playerIndex 2 = p0 slot 1, playerIndex 3 = p1 slot 1)
        ENGINE.setMove(battleKey, playerIndex + 2, moveIndex, salt, extraData);
    }

    // View functions (compatible with ICommitManager pattern)

    function getCommitment(bytes32 battleKey, address player) external view returns (bytes32 moveHash, uint256 turnId) {
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == players[0]) ? 0 : 1;
        PlayerDecisionData storage pd = playerData[battleKey][playerIndex];
        return (pd.moveHash, pd.lastCommitmentTurnId);
    }

    function getMoveCountForBattleState(bytes32 battleKey, address player) external view returns (uint256) {
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == players[0]) ? 0 : 1;
        return playerData[battleKey][playerIndex].numMovesRevealed;
    }

    function getLastMoveTimestampForPlayer(bytes32 battleKey, address player) external view returns (uint256) {
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == players[0]) ? 0 : 1;
        return playerData[battleKey][playerIndex].lastMoveTimestamp;
    }
}
