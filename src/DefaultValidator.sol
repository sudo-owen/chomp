// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Structs.sol";
import "./moves/IMoveSet.sol";

import {IEngine} from "./IEngine.sol";
import {IValidator} from "./IValidator.sol";

import {ICommitManager} from "./ICommitManager.sol";
import {IMonRegistry} from "./teams/IMonRegistry.sol";

contract DefaultValidator is IValidator {
    struct Args {
        uint256 MONS_PER_TEAM;
        uint256 MOVES_PER_MON;
        uint256 TIMEOUT_DURATION;
    }

    uint256 public constant PREV_TURN_MULTIPLIER = 2;

    uint256 immutable MONS_PER_TEAM;
    uint256 immutable BITMAP_VALUE_FOR_MONS_PER_TEAM;
    uint256 immutable MOVES_PER_MON;
    uint256 public immutable TIMEOUT_DURATION;
    IEngine immutable ENGINE;

    mapping(address => mapping(bytes32 => uint256)) proposalTimestampForProposer;

    constructor(IEngine _ENGINE, Args memory args) {
        ENGINE = _ENGINE;
        MONS_PER_TEAM = args.MONS_PER_TEAM;
        BITMAP_VALUE_FOR_MONS_PER_TEAM = (uint256(1) << args.MONS_PER_TEAM) - 1;
        MOVES_PER_MON = args.MOVES_PER_MON;
        TIMEOUT_DURATION = args.TIMEOUT_DURATION;
    }

    // Validates that there are MONS_PER_TEAM mons per team w/ MOVES_PER_MON moves each
    function validateGameStart(BattleData calldata b, ITeamRegistry teamRegistry, uint256 p0TeamIndex, uint256 p1TeamIndex
    ) external returns (bool) {
        IMonRegistry monRegistry = teamRegistry.getMonRegistry();

        // p0 and p1 each have 6 mons, each mon has 4 moves
        uint256[2] memory playerIndices = [uint256(0), uint256(1)];
        address[2] memory players = [b.p0, b.p1];
        uint256[2] memory teamIndex = [uint256(p0TeamIndex), uint256(p1TeamIndex)];

        // If either player has a team count of zero, then it's invalid
        {
            uint256 p0teamCount = teamRegistry.getTeamCount(b.p0);
            uint256 p1TeamCount = teamRegistry.getTeamCount(b.p1);
            if (p0teamCount == 0 || p1TeamCount == 0) {
                return false;
            }
        }
        // Otherwise,we check team and move length
        for (uint256 i; i < playerIndices.length; ++i) {
            if (b.teams[i].length != MONS_PER_TEAM) {
                return false;
            }

            // Should be the same length as teams[i].length
            uint256[] memory teamIndices = teamRegistry.getMonRegistryIndicesForTeam(players[i], teamIndex[i]);

            // Check that each mon is still up to date with the current mon registry values
            for (uint256 j; j < MONS_PER_TEAM; ++j) {
                if (b.teams[i][j].moves.length != MOVES_PER_MON) {
                    return false;
                }
                // Call the IMonRegistry to see if the stats, moves, and ability are still valid
                if (address(monRegistry) != address(0) && !monRegistry.validateMon(b.teams[i][j], teamIndices[j])) {
                    return false;
                }
            }
        }
        return true;
    }

    // A switch is valid if the new mon isn't knocked out and the index is valid (not out of range or the same one)
    function validateSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monToSwitchIndex)
        public
        view
        returns (bool)
    {
        uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
        if (monToSwitchIndex >= MONS_PER_TEAM) {
            return false;
        }
        bool isNewMonKnockedOut =
            ENGINE.getMonStateForBattle(battleKey, playerIndex, monToSwitchIndex, MonStateIndexName.IsKnockedOut) == 1;
        if (isNewMonKnockedOut) {
            return false;
        }
        // If it's not the zeroth turn, we cannot switch to the same mon
        // (exception for zeroth turn because we have not initiated a swap yet, so index 0 is fine)
        if (ENGINE.getTurnIdForBattleState(battleKey) != 0) {
            if (monToSwitchIndex == activeMonIndex[playerIndex]) {
                return false;
            }
        }
        return true;
    }

    function validateSpecificMoveSelection(
        bytes32 battleKey,
        uint256 moveIndex,
        uint256 playerIndex,
        bytes calldata extraData
    ) public view returns (bool) {
        uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);

        // A move cannot be selected if its stamina costs more than the mon's current stamina
        IMoveSet moveSet = ENGINE.getMoveForMonForBattle(battleKey, playerIndex, activeMonIndex[playerIndex], moveIndex);
        int256 monStaminaDelta =
            ENGINE.getMonStateForBattle(battleKey, playerIndex, activeMonIndex[playerIndex], MonStateIndexName.Stamina);
        uint256 monBaseStamina =
            ENGINE.getMonValueForBattle(battleKey, playerIndex, activeMonIndex[playerIndex], MonStateIndexName.Stamina);
        uint256 monCurrentStamina = uint256(int256(monBaseStamina) + monStaminaDelta);
        if (moveSet.stamina(battleKey, playerIndex, activeMonIndex[playerIndex]) > monCurrentStamina) {
            return false;
        } else {
            // Then, we check the move itself to see if it enforces any other specific conditions
            if (!moveSet.isValidTarget(battleKey, extraData)) {
                return false;
            }
        }
        return true;
    }

    // Validates that you can't switch to the same mon, you have enough stamina, the move isn't disabled, etc.
    function validatePlayerMove(bytes32 battleKey, uint256 moveIndex, uint256 playerIndex, bytes calldata extraData)
        external
        view
        returns (bool)
    {
        uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);

        // Enforce a switch IF:
        // - if it is the zeroth turn
        // - if the active mon is knocked out
        {
            bool isTurnZero = ENGINE.getTurnIdForBattleState(battleKey) == 0;
            bool isActiveMonKnockedOut =
                ENGINE.getMonStateForBattle(
                    battleKey, playerIndex, activeMonIndex[playerIndex], MonStateIndexName.IsKnockedOut
                ) == 1;
            if (isTurnZero || isActiveMonKnockedOut) {
                if (moveIndex != SWITCH_MOVE_INDEX) {
                    return false;
                }
            }
        }

        // Cannot go past the first 4 moves, or the switch move index or the no op
        if (moveIndex != NO_OP_MOVE_INDEX && moveIndex != SWITCH_MOVE_INDEX) {
            if (moveIndex >= MOVES_PER_MON) {
                return false;
            }
        }
        // If it is no op move, it's valid
        else if (moveIndex == NO_OP_MOVE_INDEX) {
            return true;
        }
        // If it is a switch move, then it's valid as long as the new mon isn't knocked out
        // AND if the new mon isn't the same index as the existing mon
        else if (moveIndex == SWITCH_MOVE_INDEX) {
            uint256 monToSwitchIndex = abi.decode(extraData, (uint256));
            return validateSwitch(battleKey, playerIndex, monToSwitchIndex);
        }

        // Otherwise, it's not a switch or a no-op, so it's a move
        if (!validateSpecificMoveSelection(battleKey, moveIndex, playerIndex, extraData)) {
            return false;
        }

        return true;
    }

    /*
        Check switch for turn flag:

        // 0 or 1:
        - if it's not us, then we skip
        - if it is us, then we need to check the timestamp from last turn, and we either timeout or don't

        // 2:
        - we are committing + revealing:
            - we have not committed:
                - check the timestamp from last turn, and we either timeout or don't

            - we have already committed:
                - other player has revealed
                    - check the timestamp from their reveal, and we either timeout or don't
                - other player has not revealed
                    - we don't timeout

        - we are revealing:
            - other player has not committed:
                - we don't timeout

            - other player has committed:
                - check the timestamp from their commit, and we either timeout or don't
    */
    function validateTimeout(bytes32 battleKey, uint256 playerIndexToCheck) external view returns (address loser) {
        uint256 otherPlayerIndex = (playerIndexToCheck + 1) % 2;
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        
        ICommitManager commitManager = ICommitManager(ENGINE.getMoveManager(battleKey));

        uint256 prevPlayerSwitchForTurnFlag = ENGINE.getPrevPlayerSwitchForTurnFlagForBattleState(battleKey);
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        uint256 lastTurnTimestamp;
        // If the last turn was a single player turn, and it's not the first turn (as the prev flag is always zero), we get the timestamp from their last move
        if (turnId != 0 && (prevPlayerSwitchForTurnFlag == 0 || prevPlayerSwitchForTurnFlag == 1)) {
            lastTurnTimestamp =
                commitManager.getLastMoveTimestampForPlayer(battleKey, players[prevPlayerSwitchForTurnFlag]);
        }
        // Otherwise it was either turn 0 (we grab the battle start time), or a two player turn (we grab the timestamp whoever made the last move)
        else {
            if (turnId == 0) {
                (, BattleData memory data) = ENGINE.getBattle(battleKey);
                lastTurnTimestamp = data.startTimestamp;
            } else {
                lastTurnTimestamp = commitManager.getLastMoveTimestampForPlayer(battleKey, players[(turnId - 1) % 2]);
            }
        }
        uint256 currentPlayerSwitchForTurnFlag = ENGINE.getPlayerSwitchForTurnFlagForBattleState(battleKey);

        // It's a single player turn, and it's our turn:
        if (currentPlayerSwitchForTurnFlag == playerIndexToCheck) {
            if (block.timestamp >= lastTurnTimestamp + PREV_TURN_MULTIPLIER * TIMEOUT_DURATION) {
                return players[playerIndexToCheck];
            }
        }
        // It's a two player turn:
        else if (currentPlayerSwitchForTurnFlag == 2) {
            // We are committing + revealing:
            if (turnId % 2 == playerIndexToCheck) {
                (bytes32 playerMoveHash, uint256 playerTurnId) =
                    commitManager.getCommitment(battleKey, players[playerIndexToCheck]);
                // If we have already committed:
                if (playerTurnId == turnId && playerMoveHash != bytes32(0)) {
                    // Check if other player has already revealed
                    uint256 numMovesOtherPlayerRevealed =
                        commitManager.getMoveCountForBattleState(battleKey, otherPlayerIndex);
                    uint256 otherPlayerTimestamp =
                        commitManager.getLastMoveTimestampForPlayer(battleKey, players[otherPlayerIndex]);
                    // If so, then check for timeout (no need to check if this player revealed, we assume reveal() auto-executes)
                    if (numMovesOtherPlayerRevealed > turnId) {
                        if (block.timestamp >= otherPlayerTimestamp + TIMEOUT_DURATION) {
                            return players[playerIndexToCheck];
                        }
                    }
                }
                // If we have not committed yet:
                else {
                    if (block.timestamp >= lastTurnTimestamp + PREV_TURN_MULTIPLIER * TIMEOUT_DURATION) {
                        return players[playerIndexToCheck];
                    }
                }
            }
            // We are revealing:
            else {
                (bytes32 otherPlayerMoveHash, uint256 otherPlayerTurnId) =
                    commitManager.getCommitment(battleKey, players[otherPlayerIndex]);
                // If other player has already committed:
                if (otherPlayerTurnId == turnId && otherPlayerMoveHash != bytes32(0)) {
                    uint256 otherPlayerTimestamp =
                        commitManager.getLastMoveTimestampForPlayer(battleKey, players[otherPlayerIndex]);
                    if (block.timestamp >= otherPlayerTimestamp + TIMEOUT_DURATION) {
                        return players[playerIndexToCheck];
                    }
                }
            }
        }
        return address(0);
    }
}
