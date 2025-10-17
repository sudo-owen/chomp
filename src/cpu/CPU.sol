// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";

import {IMoveSet} from "../moves/IMoveSet.sol";
import {ICPURNG} from "../rng/ICPURNG.sol";
import {IMatchmaker} from "../matchmaker/IMatchmaker.sol";
import {ICPU} from "./ICPU.sol";

import {NO_OP_MOVE_INDEX, SWITCH_MOVE_INDEX} from "../Constants.sol";

import {ExtraDataType} from "../Enums.sol";
import {Battle, BattleState, RevealedMove, ProposedBattle, Mon} from "../Structs.sol";

abstract contract CPU is ICPU, ICPURNG, IMatchmaker {

    uint256 private immutable NUM_MOVES;
    
    IEngine public immutable ENGINE;
    ICPURNG public immutable RNG;
    uint256 public nonceToUse;

    constructor(uint256 numMoves, IEngine engine, ICPURNG rng) {
        NUM_MOVES = numMoves;
        ENGINE = engine;
        if (address(rng) == address(0)) {
            RNG = ICPURNG(address(this));
        } else {
            RNG = rng;
        }
    }

    /**
     * If it's turn 0, randomly selects a mon index to swap to
     *     Otherwise, randomly selects a valid move, switch index, or no op
     */
    function selectMove(bytes32 battleKey, uint256 playerIndex)
        external virtual
        returns (uint256 moveIndex, bytes memory extraData);

    /**
     - If it's a switch needed turn, returns [VALID SWITCHES]
     - If it's a non-switch turn, returns [NO_OP | VALID MOVES | VALID SWITCHES]
     */
    function calculateValidMoves(bytes32 battleKey, uint256 playerIndex)
        public
        returns (RevealedMove[] memory, uint256 updatedNonce)
    {
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        uint256 nonce = nonceToUse;
        if (turnId == 0) {
            uint256 teamSize = ENGINE.getTeamSize(battleKey, playerIndex);
            RevealedMove[] memory switchChoices = new RevealedMove[](teamSize);
            for (uint256 i = 0; i < teamSize; i++) {
                switchChoices[i] = RevealedMove({moveIndex: SWITCH_MOVE_INDEX, salt: "", extraData: abi.encode(i)});
            }
            return (switchChoices, nonce);
        } else {
            Battle memory battle = ENGINE.getBattle(battleKey);
            uint256[] memory validSwitchIndices;
            uint256 validSwitchCount;
            uint256 validMoves = 1; // (We can always do a no op)
            // Check for valid switches
            {
                uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
                uint256 teamSize = ENGINE.getTeamSize(battleKey, playerIndex);
                validSwitchIndices = new uint256[](teamSize);
                for (uint256 i = 0; i < teamSize; i++) {
                    if (i != activeMonIndex[playerIndex]) {
                        if (
                            battle.validator.validatePlayerMove(
                                battleKey, SWITCH_MOVE_INDEX, playerIndex, abi.encode(i)
                            )
                        ) {
                            validSwitchIndices[validSwitchCount++] = i;
                        }
                    }
                }
                validMoves += validSwitchCount;
            }
            // If it's a turn where we need to make a switch, then we should just return a valid switch immediately
            {
                BattleState memory battleState = ENGINE.getBattleState(battleKey);
                if (battleState.playerSwitchForTurnFlag == 1) {
                    RevealedMove[] memory switchChoices = new RevealedMove[](validSwitchCount);
                    for (uint256 i = 0; i < validSwitchCount; i++) {
                        switchChoices[i] = RevealedMove({
                            moveIndex: SWITCH_MOVE_INDEX,
                            salt: "",
                            extraData: abi.encode(validSwitchIndices[i])
                        });
                    }
                    return (switchChoices, nonce);
                }
            }
            uint256[] memory validMoveIndices;
            bytes[] memory validMoveExtraData;
            uint256 validMoveCount;
            // Check for valid moves
            {
                uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
                validMoveIndices = new uint256[](NUM_MOVES);
                validMoveExtraData = new bytes[](NUM_MOVES);
                for (uint256 i = 0; i < NUM_MOVES; i++) {
                    IMoveSet move =
                        ENGINE.getMoveForMonForBattle(battleKey, playerIndex, activeMonIndex[playerIndex], i);
                    bytes memory extraDataToUse = "";
                    if (move.extraDataType() == ExtraDataType.SelfTeamIndex) {
                        // Skip if there are no valid switches
                        if (validSwitchCount == 0) {
                            continue;
                        }
                        uint256 randomIndex =
                            RNG.getRNG(keccak256(abi.encode(nonce++, battleKey, block.timestamp))) % validSwitchCount;
                        extraDataToUse = abi.encode(validSwitchIndices[randomIndex]);
                        validMoveExtraData[validMoveCount] = extraDataToUse;
                    }
                    if (battle.validator.validatePlayerMove(battleKey, i, playerIndex, extraDataToUse)) {
                        validMoveIndices[validMoveCount++] = i;
                    }
                }
                validMoves += validMoveCount;
            }
            RevealedMove[] memory moveChoices = new RevealedMove[](validMoves);
            moveChoices[0] = RevealedMove({moveIndex: NO_OP_MOVE_INDEX, salt: "", extraData: ""});
            for (uint256 i = 0; i < validSwitchCount; i++) {
                moveChoices[i + 1] =
                    RevealedMove({moveIndex: SWITCH_MOVE_INDEX, salt: "", extraData: abi.encode(validSwitchIndices[i])});
            }
            for (uint256 i = 0; i < validMoveCount; i++) {
                moveChoices[i + validSwitchCount + 1] =
                    RevealedMove({moveIndex: validMoveIndices[i], salt: "", extraData: validMoveExtraData[i]});
            }
            return (moveChoices, nonce);
        }
    }

    function getRNG(bytes32 seed) public pure returns (uint256) {
        return uint256(seed);
    }

    function startBattle(ProposedBattle memory proposal) external {
        ENGINE.startBattle(Battle({
            p0: proposal.p0,
            p0TeamIndex: proposal.p0TeamIndex,
            p1: proposal.p1,
            p1TeamIndex: proposal.p1TeamIndex,
            teamRegistry: proposal.teamRegistry,
            validator: proposal.validator,
            rngOracle: proposal.rngOracle,
            ruleset: proposal.ruleset,
            engineHook: proposal.engineHook,
            moveManager: proposal.moveManager,
            matchmaker: proposal.matchmaker,
            teams: new Mon[][](0)
        }));
    }

    function validateMatch(bytes32 battleKey, address player) external view returns (bool) {
        return true;
    } 
}
