// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Enums.sol";
import "./Structs.sol";

import {IEngine} from "./IEngine.sol";
import {ICommitManager} from "./ICommitManager.sol";
import {IMoveManager} from "./IMoveManager.sol";

contract FastCommitManager is ICommitManager, IMoveManager {
    // State variables
    IEngine private immutable ENGINE;
    mapping(bytes32 battleKey => mapping(address player => MoveCommitment)) private commitments;
    mapping(bytes32 battleKey => RevealedMove[][]) private moveHistory;
    mapping(bytes32 battleKey => mapping(address player => uint256)) private lastMoveTimestamp;

    // Errors
    error NotEngine();
    error NotP0OrP1();
    error AlreadyCommited();
    error AlreadyRevealed();
    error NotYetRevealed();
    error BattleNotStarted();
    error RevealBeforeOtherCommit();
    error WrongTurnId();
    error WrongPreimage();
    error PlayerNotAllowed();
    error InvalidMove(address player);

    // Events
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
        address[] memory p0AndP1 = ENGINE.getPlayersForBattle(battleKey);
        address caller = msg.sender;

        // 1) Only battle participants can commit
        if (caller != p0AndP1[0] && caller != p0AndP1[1]) {
            revert NotP0OrP1();
        }

        // 2) Can only commit moves to battles with a Started status
        // (reveal relies on commit, and execute relies on both of those)
        // (so transitively, it's safe to just check battle proposal status on commit)
        if (ENGINE.getBattleStatus(battleKey) != GameStatus.Started) {
            revert BattleNotStarted();
        }

        // 3) Validate no commitment already exists for this turn:
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);

        // 4) If it's the zeroth turn, require that no hash is set for the player
        // otherwise, just check if the turn id (which we overwrite each turn) is in sync
        // (if we already committed this turn, then the turn id should match)
        if (turnId == 0) {
            if (commitments[battleKey][caller].moveHash != bytes32(0)) {
                revert AlreadyCommited();
            }
        } else if (commitments[battleKey][caller].turnId == turnId) {
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
        commitments[battleKey][caller] = MoveCommitment({moveHash: moveHash, turnId: turnId});
        lastMoveTimestamp[battleKey][caller] = block.timestamp;

        // 8) Initialize move history if it's the first commit
        if (moveHistory[battleKey].length == 0) {
            moveHistory[battleKey].push();
            moveHistory[battleKey].push();
        }

        emit MoveCommit(battleKey, caller);
    }

    function revealMove(bytes32 battleKey, uint256 moveIndex, bytes32 salt, bytes calldata extraData, bool autoExecute)
        external
    {
        // 1) Only battle participants can reveal
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
        address otherPlayer = p0AndP1[otherPlayerIndex];

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
                    if (commitments[battleKey][otherPlayer].turnId != turnId) {
                        revert RevealBeforeOtherCommit();
                    }
                }
                // If it is the zeroth turn, do the same check, but check moveHash instead of turnId (which would be zero)
                else {
                    if (commitments[battleKey][otherPlayer].moveHash == bytes32(0)) {
                        revert RevealBeforeOtherCommit();
                    }
                }
            }
            // (Otherwise, it's a single player turn, so we don't need to check for an existing commitment)
        }
        // 3) Otherwise (we need to both commit + reveal), so we need to check:
        // - the preimage checks out
        // - reveal happens after a commit
        // - the other player has already *revealed*
        else {
            // - validate preimage
            MoveCommitment storage commitment = commitments[battleKey][msg.sender];
            if (keccak256(abi.encodePacked(moveIndex, salt, extraData)) != commitment.moveHash) {
                revert WrongPreimage();
            }

            // - ensure reveal happens after caller commits
            if (commitment.turnId != turnId) {
                revert WrongTurnId();
            }

            // - check that other player has already revealed
            RevealedMove[] storage otherPlayerMoveHistory = moveHistory[battleKey][otherPlayerIndex];
            if (otherPlayerMoveHistory.length < turnId) {
                revert NotYetRevealed();
            }
        }

        // 4) Regardless, we still need to check (for all players that) there was no prior reveal
        // (prevents double revealing)
        RevealedMove[] storage playerMoveHistory = moveHistory[battleKey][currentPlayerIndex];
        if (playerMoveHistory.length > turnId) {
            revert AlreadyRevealed();
        }

        // 5) Validate that the commited moves are legal
        // (e.g. there is enough stamina, move is not disabled, etc.)
        if (
            !ENGINE.getBattleValidator(battleKey).validatePlayerMove(battleKey, moveIndex, currentPlayerIndex, extraData)
        ) {
            revert InvalidMove(msg.sender);
        }

        // 6) Store revealed move and extra data for the current player
        // Update their last move timestamp
        playerMoveHistory.push(RevealedMove({moveIndex: moveIndex, salt: salt, extraData: extraData}));
        lastMoveTimestamp[battleKey][msg.sender] = block.timestamp;

        // 7) Store empty move for other player if it's a turn where only a single player has to make a move
        if (playerSwitchForTurnFlag == 0 || playerSwitchForTurnFlag == 1) {
            RevealedMove[] storage otherPlayerMoveHistory = moveHistory[battleKey][otherPlayerIndex];
            otherPlayerMoveHistory.push(RevealedMove({moveIndex: NO_OP_MOVE_INDEX, salt: "", extraData: ""}));
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

    function getCommitment(bytes32 battleKey, address player) external view returns (MoveCommitment memory) {
        return commitments[battleKey][player];
    }

    function getMoveForBattleStateForTurn(bytes32 battleKey, uint256 playerIndex, uint256 turn)
        external
        view
        returns (RevealedMove memory)
    {
        return moveHistory[battleKey][playerIndex][turn];
    }

    function getMoveCountForBattleState(bytes32 battleKey, uint256 playerIndex) external view returns (uint256) {
        return moveHistory[battleKey][playerIndex].length;
    }

    function getLastMoveTimestampForPlayer(bytes32 battleKey, address player) external view returns (uint256) {
        return lastMoveTimestamp[battleKey][player];
    }
}
