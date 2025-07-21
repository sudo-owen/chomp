// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";
import {IValidator} from "../IValidator.sol";
import {ICPU} from "./ICPU.sol";
import {IMoveSet} from "../moves/IMoveSet.sol";

import {NO_OP_MOVE_INDEX, SWITCH_MOVE_INDEX} from "../Constants.sol";
import {Battle, RevealedMove} from "../Structs.sol";
import {ExtraDataType} from "../Enums.sol";

contract RandomCPU is ICPU {

    // Hard coded for now
    uint256 constant NUM_MOVES = 4;

    IEngine private immutable ENGINE;

    constructor(IEngine engine) {
        ENGINE = engine;
    }

    /*
    - If it's turn index 0, randomly pick a mon index
    - If it's not turn 0, check for all valid switches (among all mon indices)
    - Check for all valid moves
    - Pick one
    */
    function selectMove(bytes32 battleKey, uint256 playerIndex)
        external
        returns (uint256 moveIndex, bytes memory extraData)
    {
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        if (turnId == 0) {
            uint256 teamSize = ENGINE.getTeamSize(battleKey, playerIndex);
            uint256 monToSwitchIndex = uint256(keccak256(abi.encode(battleKey, block.timestamp))) % teamSize;
            return (SWITCH_MOVE_INDEX, abi.encode(monToSwitchIndex));
        } else {
            Battle memory battle = ENGINE.getBattle(battleKey);
            uint256[] memory validSwitchIndices;
            uint256 validSwitchCount;
            uint256 validMoves = 1; // We can always do a no op
            // Check for valid switches
            {
                uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
                uint256 teamSize = ENGINE.getTeamSize(battleKey, playerIndex);
                validSwitchIndices = new uint256[](teamSize);
                for (uint256 i = 0; i < teamSize; i++) {
                    if (i != activeMonIndex[playerIndex]) {
                        if (battle.validator.validatePlayerMove(battleKey, SWITCH_MOVE_INDEX, playerIndex, abi.encode(i))) {
                            validSwitchIndices[validSwitchCount++] = i;
                        }
                    }
                }
                validMoves += validSwitchCount;
            }
            uint256[] memory validMoveIndices;
            bytes[] memory validMoveExtraData;
            uint256 validMoveCount;
            // Check for valid moves
            {
                uint256[] memory activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
                validMoveIndices = new uint256[](NUM_MOVES);
                for (uint256 i = 0; i < NUM_MOVES; i++) {
                    IMoveSet move = ENGINE.getMoveForMonForBattle(battleKey, playerIndex, activeMonIndex[playerIndex], i);
                    bytes memory extraDataToUse;
                    if (move.extraDataType() == ExtraDataType.SelfTeamIndex) {
                        uint256 teamSize = ENGINE.getTeamSize(battleKey, playerIndex);
                        uint256 randomIndex = uint256(keccak256(abi.encode(battleKey, block.timestamp))) % teamSize;
                        extraDataToUse = abi.encode(randomIndex);
                        validMoveExtraData[validMoveCount] = extraDataToUse;
                    }
                    if (battle.validator.validatePlayerMove(battleKey, i, playerIndex, extraDataToUse)) {
                        validMoveIndices[validMoveCount++] = i;
                    }
                }
                validMoves += validMoveCount;
            }
            // Pick a random move
            RevealedMove[] memory moveChoices = new RevealedMove[](validMoves);
            moveChoices[0] = RevealedMove({moveIndex: NO_OP_MOVE_INDEX, salt: "", extraData: ""});
            for (uint256 i = 0; i < validSwitchCount; i++) {
                moveChoices[i + 1] = RevealedMove({moveIndex: SWITCH_MOVE_INDEX, salt: "", extraData: abi.encode(validSwitchIndices[i])});
            }
            for (uint256 i = 0; i < validMoveCount; i++) {
                moveChoices[i + validSwitchCount + 1] = RevealedMove({moveIndex: validMoveIndices[i], salt: "", extraData: validMoveExtraData[i]});
            }
            uint256 choiceIndex = uint256(keccak256(abi.encode(battleKey, block.timestamp))) % validMoves;
            return (moveChoices[choiceIndex].moveIndex, moveChoices[choiceIndex].extraData);
        }
    }

    function acceptBattle(bytes32 battleKey, uint256 p1TeamIndex, bytes32 battleIntegrityHash) external {
        ENGINE.acceptBattle(battleKey, p1TeamIndex, battleIntegrityHash);
    }
}
