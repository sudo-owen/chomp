// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";
import {ICPURNG} from "../rng/ICPURNG.sol";
import {CPU} from "./CPU.sol";
import {RevealedMove} from "../Structs.sol";
import {TypeCalculator} from "../types/TypeCalculator.sol";
import {MonStateIndexName, Type, MoveClass} from "../Enums.sol";
import {IMoveSet} from "../moves/IMoveSet.sol";

contract OkayCPU is CPU {

    TypeCalculator public immutable TYPE_CALC;

    constructor(uint256 numMoves, IEngine engine, ICPURNG rng, TypeCalculator typeCalc) CPU(numMoves, engine, rng) {
        TYPE_CALC = typeCalc;
    }

    /**
     * If it's turn 0, swap in a mon that resists the other player's type1 (if possible)
     */
    function selectMove(bytes32 battleKey, uint256 playerIndex)
        external
        override
        returns (uint256 moveIndex, bytes memory extraData)
    {
        (RevealedMove[] memory noOp, RevealedMove[] memory moves, RevealedMove[] memory switches) = calculateValidMoves(battleKey, playerIndex);

        // Merge all three arrays into one
        uint256 totalChoices = noOp.length + moves.length + switches.length;
        RevealedMove[] memory allChoices = new RevealedMove[](totalChoices);
        {
            uint256 index = 0;
            for (uint256 i = 0; i < noOp.length; i++) {
                allChoices[index++] = noOp[i];
            }
            for (uint256 i = 0; i < moves.length; i++) {
                allChoices[index++] = moves[i];
            }
            for (uint256 i = 0; i < switches.length; i++) {
                allChoices[index++] = switches[i];
            }
        }
        uint256 opponentIndex = (playerIndex + 1) % 2;
        RevealedMove memory opponentMove = ENGINE.getMoveManager(battleKey)
            .getMoveForBattleStateForTurn(battleKey, opponentIndex, ENGINE.getTurnIdForBattleState(battleKey));
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);

        // If it's the first turn, try and find a mon who has a type advantage to the opponent's type1
        if (turnId == 0) {
            Type opponentType1 = Type(ENGINE.getMonValueForBattle(battleKey, opponentIndex, abi.decode(opponentMove.extraData, (uint256)), MonStateIndexName.Type1));
            Type[] memory selfTypes = new Type[](switches.length);
            for (uint256 i = 0; i < switches.length; i++) {
                selfTypes[i] = Type(ENGINE.getMonValueForBattle(battleKey, playerIndex, abi.decode(switches[i].extraData, (uint256)), MonStateIndexName.Type1));
            }
            int256 bestIndex = _getTypeAdvantageOrNullToDefend(opponentType1, selfTypes);
            if (bestIndex != -1) {
                return (switches[uint256(bestIndex)].moveIndex, switches[uint256(bestIndex)].extraData);
            }
            else {
                uint256 rngIndex = _getRNG(battleKey) % switches.length;
                return (switches[rngIndex].moveIndex, switches[rngIndex].extraData);
            }
        } 
        /*
            Otherwise, if:
            - We have 2 or less stamina, we rest (75%) or swap (if possible)
            - If we are at full health, try and choose a non MoveClass.Physical or MoveClass.Special move if possible
            - If we are not at full health, try and choose a MoveClass.Physical or MoveClass.Special move (with advantage) if possible
            - Otherwise, do a smart random select
        */
        else {
            int32 staminaDelta = ENGINE.getMonStateForBattle(battleKey, playerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex], MonStateIndexName.Stamina);
            if (staminaDelta <= -3) {
                if (_getRNG(battleKey) % 4 != 0) {
                    return (noOp[0].moveIndex, noOp[0].extraData);
                } else {
                    uint256 rngIndex = _getRNG(battleKey) % switches.length;
                    return (switches[rngIndex].moveIndex, switches[rngIndex].extraData);
                }
            }
            else {
                int256 hpDelta = ENGINE.getMonStateForBattle(battleKey, playerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex], MonStateIndexName.Hp);
                if (hpDelta == 0) {
                    uint256 numAttackMoves = 0;
                    for (uint256 i = 0; i < moves.length; i++) {
                        MoveClass currentMoveClass = ENGINE.getMoveForMonForBattle(battleKey, playerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex], moves[i].moveIndex).moveClass(battleKey);
                        if (currentMoveClass == MoveClass.Physical || currentMoveClass == MoveClass.Special) {
                            numAttackMoves++;
                        }
                    }
                    IMoveSet[] memory attackMoves = new IMoveSet[](numAttackMoves);
                    uint256 attackMovesIndex = 0;
                    for (uint256 i = 0; i < moves.length; i++) {
                        MoveClass currentMoveClass = ENGINE.getMoveForMonForBattle(battleKey, playerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex], moves[i].moveIndex).moveClass(battleKey);
                        if (currentMoveClass == MoveClass.Physical || currentMoveClass == MoveClass.Special) {
                            attackMoves[attackMovesIndex++] = ENGINE.getMoveForMonForBattle(battleKey, playerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex], moves[i].moveIndex);
                        }
                    }
                    Type opponentType1 = Type(ENGINE.getMonValueForBattle(battleKey, opponentIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[opponentIndex], MonStateIndexName.Type1));
                    Type opponentType2 = Type(ENGINE.getMonValueForBattle(battleKey, opponentIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[opponentIndex], MonStateIndexName.Type2));
                    int256 attackIndex = _getTypeAdvantageOrNullToAttack(battleKey, opponentType1, opponentType2, attackMoves);
                    if (attackIndex != -1) {
                        return (moves[uint256(attackIndex)].moveIndex, moves[uint256(attackIndex)].extraData);
                    }
                }
                return _smartRandomSelect(battleKey, noOp, moves, switches);
            }
        }
    }

    function _getRNG(bytes32 battleKey) internal returns (uint256) {
        return RNG.getRNG(keccak256(abi.encode(nonceToUse++, battleKey, block.timestamp)));
    }

    // Biased towards moves versus swapping or resting
    function _smartRandomSelect(bytes32 battleKey, RevealedMove[] memory noOp, RevealedMove[] memory moves, RevealedMove[] memory switches) internal returns (uint256, bytes memory) {
        uint256 rngIndex = _getRNG(battleKey);
        uint256 adjustedTotalMovesDenom = moves.length + 1;
        if (rngIndex % adjustedTotalMovesDenom == 0) {
            uint256 switchOrNoOp = _getRNG(battleKey) % 2;
            if (switchOrNoOp == 0) {
                return (noOp[0].moveIndex, noOp[0].extraData);
            } else {
                uint256 rngSwitchIndex = _getRNG(battleKey) % switches.length;
                return (switches[rngSwitchIndex].moveIndex, switches[rngSwitchIndex].extraData);
            }
        } else {
            uint256 moveIndex = _getRNG(battleKey) % moves.length;
            return (moves[moveIndex].moveIndex, moves[moveIndex].extraData);
        }
    }

    function _getTypeAdvantageOrNullToAttack(bytes32 battleKey, Type defenderType1, Type defenderType2, IMoveSet[] memory attacks) internal view returns (int) {
        for (uint256 i = 0; i < attacks.length; i++) {
            uint256 effectiveness = TYPE_CALC.getTypeEffectiveness(attacks[i].moveType(battleKey), defenderType1, 2);
            if (defenderType2 != Type.None) {
                uint256 effectiveness2 = TYPE_CALC.getTypeEffectiveness(attacks[i].moveType(battleKey), defenderType2, 2);
                effectiveness = (effectiveness * effectiveness2);
            }
            if (effectiveness > 2) {
                return int256(i);
            }
        }
        return -1;
    }

    function _getTypeAdvantageOrNullToDefend(Type attackerType, Type[] memory defenderTypes) internal view returns (int) {
        for (uint256 i = 0; i < defenderTypes.length; i++) {
            uint256 effectiveness = TYPE_CALC.getTypeEffectiveness(attackerType, defenderTypes[i], 2);
            if (effectiveness == 0 || effectiveness == 1) {
                return int256(i);
            }
        }
        return -1;
    }
}
