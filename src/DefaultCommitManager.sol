// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Enums.sol";
import "./Structs.sol";

import {ICommitManager} from "./ICommitManager.sol";
import {IEngine} from "./IEngine.sol";

contract DefaultCommitManager is ICommitManager {
    IEngine private immutable ENGINE;

    mapping(bytes32 battleKey => mapping(uint256 playerIndex => PlayerDecisionData)) private playerData;

    error NotP0OrP1();
    error AlreadyCommited();
    error AlreadyRevealed();
    error NotYetRevealed();
    error RevealBeforeOtherCommit();
    error RevealBeforeSelfCommit();
    error WrongPreimage();
    error PlayerNotAllowed();
    error InvalidMove(address player);
    error BattleNotYetStarted();
    error BattleAlreadyComplete();

    event MoveCommit(bytes32 indexed battleKey, address player);
    event MoveReveal(bytes32 indexed battleKey, address player, uint256 moveIndex);

    constructor(IEngine engine) {
        ENGINE = engine;
    }

    /**
     * Committing is for:
     *     - p0 if the turn index % 2 == 0
     *     - p1 if the turn index % 2 == 1
     *     - UNLESS there is a player switch for turn flag, in which case, no commits at all
     */
    function commitMove(bytes32 battleKey, bytes32 moveHash) external {
        // Can only commit moves to battles with nonzero timestamp and address(0) winner
        uint256 startTimestamp = ENGINE.getStartTimestamp(battleKey);
        if (startTimestamp == 0) {
            revert BattleNotYetStarted();
        }

        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        address caller = msg.sender;
        uint256 playerIndex = (caller == p0AndP1[0]) ? 0 : 1;

        // Only battle participants can commit
        if (caller != p0AndP1[0] && caller != p0AndP1[1]) {
            revert NotP0OrP1();
        }

        address winner = ENGINE.getWinner(battleKey);
        if (winner != address(0)) {
            revert BattleAlreadyComplete();
        }

        // 3) Validate no commitment already exists for this turn:
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);

        // If it's the zeroth turn, require that no hash is set for the player
        // otherwise, just check if the turn id (which we overwrite each turn) is in sync
        // (if we already committed this turn, then the turn id should match)
        if (turnId == 0) {
            if (playerData[battleKey][playerIndex].moveHash != bytes32(0)) {
                revert AlreadyCommited();
            }
        } else if (playerData[battleKey][playerIndex].lastCommitmentTurnId == turnId) {
            revert AlreadyCommited();
        }

        // 5) Cannot commit if the battle state says it's only for one player
        uint256 playerSwitchForTurnFlag = ENGINE.getPlayerSwitchForTurnFlagForBattleState(battleKey);
        if (playerSwitchForTurnFlag != 2) {
            revert PlayerNotAllowed();
        }

        // 6) Can only commit if the turn index % lines up with the player index
        // (Otherwise, just go straight to revealing)
        if (caller == p0AndP1[0] && turnId % 2 == 1) {
            revert PlayerNotAllowed();
        } else if (caller == p0AndP1[1] && turnId % 2 == 0) {
            revert PlayerNotAllowed();
        }

        // 7) Store the commitment
        playerData[battleKey][playerIndex].lastCommitmentTurnId = uint16(turnId);
        playerData[battleKey][playerIndex].moveHash = moveHash;
        playerData[battleKey][playerIndex].lastMoveTimestamp = uint96(block.timestamp);

        emit MoveCommit(battleKey, caller);
    }

    event Foo(uint a, uint b);

    function revealMove(bytes32 battleKey, uint128 moveIndex, bytes32 salt, bytes calldata extraData, bool autoExecute)
        external
    {
        // Can only commit moves to battles with nonzero timestamp and address(0) winner
        uint256 startTimestamp = ENGINE.getStartTimestamp(battleKey);
        if (startTimestamp == 0) {
            revert BattleNotYetStarted();
        }

        // Only battle participants can reveal
        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        if (msg.sender != p0AndP1[0] && msg.sender != p0AndP1[1]) {
            revert NotP0OrP1();
        }

        // Set current and other player based on the caller
        uint256 currentPlayerIndex;
        uint256 otherPlayerIndex;
        if (msg.sender == p0AndP1[0]) {
            otherPlayerIndex = 1;
        } else {
            currentPlayerIndex = 1;
        }

        address winner = ENGINE.getWinner(battleKey);
        if (winner != address(0)) {
            revert BattleAlreadyComplete();
        }

        // Get turn id and switch for turn flag
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        uint256 playerSwitchForTurnFlag = ENGINE.getPlayerSwitchForTurnFlagForBattleState(battleKey);

        // 2) If the turn index does NOT line up with the player index
        // OR it's a turn with only one player, and that player is us:
        // Then we don't need to check the preimage
        bool playerSkipsPreimageCheck;
        if (playerSwitchForTurnFlag == 2) {
            playerSkipsPreimageCheck =
                (((turnId % 2 == 1) && (currentPlayerIndex == 0)) || ((turnId % 2 == 0) && (currentPlayerIndex == 1)));
        } else {
            playerSkipsPreimageCheck = (playerSwitchForTurnFlag == currentPlayerIndex);

            // We cannot reveal if the player index is different than the switch for turn flag
            // (if it's a one player turn, but it's not our turn to reveal)
            if (!playerSkipsPreimageCheck) {
                revert PlayerNotAllowed();
            }
        }
        if (playerSkipsPreimageCheck) {
            // If it's a 2 player turn (and we can skip the preimage verification),
            // then we check to see if an existing commitment from the other player exists
            // (we can only reveal after other player commit)
            if (playerSwitchForTurnFlag == 2) {
                // If it's not the zeroth turn, make sure that player cannot reveal until other player has committed
                if (turnId != 0) {
                    if (playerData[battleKey][otherPlayerIndex].lastCommitmentTurnId != turnId) {
                        revert RevealBeforeOtherCommit();
                    }
                }
                // If it is the zeroth turn, do the same check, but check moveHash instead of turnId (which would be zero)
                else {
                    if (playerData[battleKey][otherPlayerIndex].moveHash == bytes32(0)) {
                        revert RevealBeforeOtherCommit();
                    }
                }
            }
            // (Otherwise, it's a single player turn, so we don't need to check for an existing commitment)
        }
        // 3) Otherwise (we need to both commit + reveal), so we need to check:
        // - the preimage checks out
        // - reveal happens after a commit
        // - the other player has already revealed
        else {
            // - validate preimage
            if (keccak256(abi.encodePacked(moveIndex, salt, extraData)) != playerData[battleKey][currentPlayerIndex].moveHash) {
                revert WrongPreimage();
            }

            // - ensure reveal happens after caller commits
            if (playerData[battleKey][currentPlayerIndex].lastCommitmentTurnId != turnId) {
                revert RevealBeforeSelfCommit();
            }

            // - check that other player has already revealed (i.e. a nonzero last move timestamp)
            if (playerData[battleKey][otherPlayerIndex].numMovesRevealed < turnId || playerData[battleKey][otherPlayerIndex].lastMoveTimestamp == 0) {
                revert NotYetRevealed();
            }
        }

        // 4) Regardless, we still need to check there was no prior reveal (prevents double revealing)
        if (playerData[battleKey][currentPlayerIndex].numMovesRevealed > turnId) {
            revert AlreadyRevealed();
        }

        // 5) Validate that the commited moves are legal
        // (e.g. there is enough stamina, move is not disabled, etc.)
        if (!ENGINE.getBattleValidator(battleKey)
                .validatePlayerMove(battleKey, moveIndex, currentPlayerIndex, extraData)) {
            revert InvalidMove(msg.sender);
        }

        // 6) Store revealed move and extra data for the current player
        // Update their last move timestamp and num moves revealed
        ENGINE.setMove(battleKey, currentPlayerIndex, moveIndex, salt, extraData);
        playerData[battleKey][currentPlayerIndex].lastMoveTimestamp = uint96(block.timestamp);
        playerData[battleKey][currentPlayerIndex].numMovesRevealed += 1;

        // 7) Store empty move for other player if it's a turn where only a single player has to make a move
        if (playerSwitchForTurnFlag == 0 || playerSwitchForTurnFlag == 1) {
            // TODO: add this later to mutate the engine directly
            playerData[battleKey][otherPlayerIndex].lastMoveTimestamp = uint96(block.timestamp);
            playerData[battleKey][otherPlayerIndex].numMovesRevealed += 1;
        }

        // 8) Emit move reveal event before game engine execution
        emit MoveReveal(battleKey, msg.sender, moveIndex);

        // 9) Auto execute if desired/available
        if (autoExecute) {
            // We can execute if:
            // - it's a single player turn (no other commitments to wait on)
            // - we're the player who previously committed (the other party already revealed)
            if ((playerSwitchForTurnFlag == currentPlayerIndex) || (!playerSkipsPreimageCheck)) {
                ENGINE.execute(battleKey);
            }
        }
    }

    function getCommitment(bytes32 battleKey, address player) external view returns (bytes32 moveHash, uint256 turnId) {
        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == p0AndP1[0]) ? 0 : 1;
        return (
            playerData[battleKey][playerIndex].moveHash,
            playerData[battleKey][playerIndex].lastCommitmentTurnId
        );
    }

    function getMoveCountForBattleState(bytes32 battleKey, address player) external view returns (uint256) {
        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == p0AndP1[0]) ? 0 : 1;
        return playerData[battleKey][playerIndex].numMovesRevealed;
    }

    function getLastMoveTimestampForPlayer(bytes32 battleKey, address player) external view returns (uint256) {
        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        uint256 playerIndex = (player == p0AndP1[0]) ? 0 : 1;
        return playerData[battleKey][playerIndex].lastMoveTimestamp;
    }
}
