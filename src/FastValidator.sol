// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Structs.sol";
import "./moves/IMoveSet.sol";

import {IEngine} from "./IEngine.sol";
import {IValidator} from "./IValidator.sol";

import {ICommitManager} from "./ICommitManager.sol";
import {IMoveManager} from "./IMoveManager.sol";
import {IMonRegistry} from "./teams/IMonRegistry.sol";
import {ITeamRegistry} from "./teams/ITeamRegistry.sol";

contract FastValidator is IValidator {
    struct Args {
        uint256 MONS_PER_TEAM;
        uint256 MOVES_PER_MON;
        uint256 TIMEOUT_DURATION;
    }

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
    function validateGameStart(
        Battle calldata b,
        ITeamRegistry teamRegistry,
        uint256 p0TeamIndex,
        bytes32 battleKey,
        address gameStartCaller
    ) external returns (bool) {
        IMonRegistry monRegistry = teamRegistry.getMonRegistry();

        // p0 and p1 each have 6 mons, each mon has 4 moves
        uint256[2] memory playerIndices = [uint256(0), uint256(1)];
        address[2] memory players = [b.p0, b.p1];
        uint256[2] memory teamIndex = [p0TeamIndex, b.p1TeamIndex];

        // If either player has a team count of zero, then it's invalid
        {
            uint256 p0teamCount = teamRegistry.getTeamCount(b.p0);
            uint256 p1TeamCount = teamRegistry.getTeamCount(b.p1);
            if (p0teamCount == 0 || p1TeamCount == 0) {
                return false;
            }
        }

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
        uint256 previousProposalTimestamp = proposalTimestampForProposer[gameStartCaller][battleKey];
        // Ensures that proposers cannot quickly modify in-flight proposed matches by rate limiting
        if (previousProposalTimestamp != 0) {
            if (block.timestamp - previousProposalTimestamp < TIMEOUT_DURATION) {
                return false;
            }
        }
        proposalTimestampForProposer[gameStartCaller][battleKey] = block.timestamp;
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
            bool isActiveMonKnockedOut = ENGINE.getMonStateForBattle(
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

    // Validates that the game is over, returns address(0) if no winner, otherwise returns the winner
    function validateGameOver(bytes32 battleKey, uint256 priorityPlayerIndex) external view returns (address) {
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);

        // A game is over if all of a player's mons are knocked out
        uint256[2] memory playerIndex = [uint256(0), uint256(1)];
        if (priorityPlayerIndex == 1) {
            playerIndex = [uint256(1), uint256(0)];
        }
        for (uint256 i; i < playerIndex.length; ++i) {
            uint256 monsKOedBitmapValue = ENGINE.getMonKOCount(battleKey, playerIndex[i]);
            if (monsKOedBitmapValue == BITMAP_VALUE_FOR_MONS_PER_TEAM) {
                if (playerIndex[i] == 0) {
                    return players[1];
                } else {
                    return players[0];
                }
            }
        }
        return address(0);
    }

    function validateTimeout(bytes32 battleKey, uint256 presumedAFKPlayerIndex) external view returns (address) {
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        uint256 presumedHonestPlayerIndex = (presumedAFKPlayerIndex + 1) % 2;
        address presumedHonestPlayer;
        address presumedAFKPlayer;
        if (presumedHonestPlayerIndex == 0) {
            presumedHonestPlayer = players[0];
            presumedAFKPlayer = players[1];
        } else {
            presumedHonestPlayer = players[1];
            presumedAFKPlayer = players[0];
        }

        ICommitManager commitManager = ICommitManager(address(ENGINE.getMoveManager(battleKey)));

        // Grab latest reference time out of both players
        uint256 lastMoveTimestamp;
        {
            uint256 p0LastTimestamp = commitManager.getLastMoveTimestampForPlayer(battleKey, players[0]);
            uint256 p1LastTimestamp = commitManager.getLastMoveTimestampForPlayer(battleKey, players[1]);
            lastMoveTimestamp = p0LastTimestamp > p1LastTimestamp ? p0LastTimestamp : p1LastTimestamp;
        }
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        uint256 playerSwitchForTurnFlag = ENGINE.getPlayerSwitchForTurnFlagForBattleState(battleKey);

        // If the presumed AFK player has to commit and it's a 2 player turn...
        if ((playerSwitchForTurnFlag == 2) && (turnId % 2 == presumedAFKPlayerIndex)) {
            // Check existing commitment to see if a commitment for this turn exists yet
            MoveCommitment memory playerCommitment = commitManager.getCommitment(battleKey, presumedAFKPlayer);
            // If a commitment doesn't exist, and it's been more than TIMEOUT, then they lose
            bool noCommitment = (playerCommitment.turnId < turnId)
                || (playerCommitment.turnId == 0 && playerCommitment.moveHash == bytes32(0));
            if (noCommitment && (block.timestamp >= lastMoveTimestamp + TIMEOUT_DURATION)) {
                return presumedHonestPlayer;
            }
            // If a commitment from the player does exist...
            if (playerCommitment.turnId == turnId) {
                uint256 movesPresumedHonestPlayerRevealed =
                    commitManager.getMoveCountForBattleState(battleKey, presumedHonestPlayerIndex);
                // And the other player has already revealed...
                if (movesPresumedHonestPlayerRevealed > turnId) {
                    // Check if the presumed AFK player has revealed yet
                    uint256 movesPresumedAFKPlayerRevealed =
                        commitManager.getMoveCountForBattleState(battleKey, presumedAFKPlayerIndex);
                    // If not, and it's been more than TIMEOUT, then they lose (i.e. return the other player)
                    if (
                        (movesPresumedAFKPlayerRevealed <= turnId)
                            && (block.timestamp >= lastMoveTimestamp + TIMEOUT_DURATION)
                    ) {
                        return presumedHonestPlayer;
                    }
                }
            }
        }
        // If it's a one-player turn, and it's the presumed afk player's turn...
        // Or, it's a two-player turn, and it's the presumed afk player only has to reveal...
        if (
            (playerSwitchForTurnFlag != 2 && playerSwitchForTurnFlag == presumedAFKPlayerIndex)
                || (playerSwitchForTurnFlag == 2 && turnId % 2 != presumedAFKPlayerIndex)
        ) {
            // Check if the presumed AFK player has revealed yet
            uint256 movesPresumedAFKPlayerRevealed =
                commitManager.getMoveCountForBattleState(battleKey, presumedAFKPlayerIndex);
            // If not, and it's been more than TIMEOUT, then they lose (i.e. return the other player)
            if ((movesPresumedAFKPlayerRevealed <= turnId) && (block.timestamp >= lastMoveTimestamp + TIMEOUT_DURATION))
            {
                return presumedHonestPlayer;
            }
        }
        return address(0);
    }

    function computePriorityPlayerIndex(bytes32 battleKey, uint256 rng) external view returns (uint256) {
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);

        IMoveManager moveManager = ENGINE.getMoveManager(battleKey);
        
        RevealedMove memory p0Move = moveManager.getMoveForBattleStateForTurn(battleKey, 0, turnId);
        RevealedMove memory p1Move = moveManager.getMoveForBattleStateForTurn(battleKey, 1, turnId);
        uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);

        uint256 p0Priority;
        uint256 p1Priority;

        // Call the move for its priority, unless it's the switch or no op move index
        {
            if (p0Move.moveIndex == SWITCH_MOVE_INDEX || p0Move.moveIndex == NO_OP_MOVE_INDEX) {
                p0Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p0MoveSet = ENGINE.getMoveForMonForBattle(battleKey, 0, activeMonIndex[0], p0Move.moveIndex);
                p0Priority = p0MoveSet.priority(battleKey, 0);
            }

            if (p1Move.moveIndex == SWITCH_MOVE_INDEX || p1Move.moveIndex == NO_OP_MOVE_INDEX) {
                p1Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p1MoveSet = ENGINE.getMoveForMonForBattle(battleKey, 1, activeMonIndex[1], p1Move.moveIndex);
                p1Priority = p1MoveSet.priority(battleKey, 1);
            }
        }

        // Determine priority based on (in descending order of importance):
        // - the higher priority tier
        // - within same priority, the higher speed
        // - if both are tied, use the rng value
        if (p0Priority > p1Priority) {
            return 0;
        } else if (p0Priority < p1Priority) {
            return 1;
        } else {
            uint32 p0MonSpeed = uint32(
                int32(ENGINE.getMonValueForBattle(battleKey, 0, activeMonIndex[0], MonStateIndexName.Speed))
                    + ENGINE.getMonStateForBattle(battleKey, 0, activeMonIndex[0], MonStateIndexName.Speed)
            );
            uint32 p1MonSpeed = uint32(
                int32(ENGINE.getMonValueForBattle(battleKey, 1, activeMonIndex[1], MonStateIndexName.Speed))
                    + ENGINE.getMonStateForBattle(battleKey, 1, activeMonIndex[1], MonStateIndexName.Speed)
            );
            if (p0MonSpeed > p1MonSpeed) {
                return 0;
            } else if (p0MonSpeed < p1MonSpeed) {
                return 1;
            } else {
                return rng % 2;
            }
        }
    }
}
