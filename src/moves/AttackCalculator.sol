// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Constants.sol";
import "../Enums.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {ITypeCalculator} from "../types/ITypeCalculator.sol";

library AttackCalculator {
    uint32 constant RNG_SCALING_DENOM = 100;

    function _calculateDamage(
        IEngine ENGINE,
        ITypeCalculator TYPE_CALCULATOR,
        bytes32 battleKey,
        uint256 attackerPlayerIndex,
        uint32 basePower,
        uint32 accuracy, // out of 100
        uint256 volatility,
        Type attackType,
        MoveClass attackSupertype,
        uint256 rng,
        uint256 critRate // out of 100
    ) internal returns (int32, EngineEventType) {
        uint256 defenderPlayerIndex = (attackerPlayerIndex + 1) % 2;
        (int32 damage, EngineEventType eventType) = _calculateDamageView(
            ENGINE,
            TYPE_CALCULATOR,
            battleKey,
            attackerPlayerIndex,
            defenderPlayerIndex,
            basePower,
            accuracy,
            volatility,
            attackType,
            attackSupertype,
            rng,
            critRate
        );
        uint256[] memory monIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
        if (damage != 0) {
            ENGINE.dealDamage(defenderPlayerIndex, monIndex[defenderPlayerIndex], damage);
        }
        if (eventType != EngineEventType.None) {
            ENGINE.emitEngineEvent(eventType, "");
        }
        return (damage, eventType);
    }

    function _calculateDamageView(
        IEngine ENGINE,
        ITypeCalculator TYPE_CALCULATOR,
        bytes32 battleKey,
        uint256 attackerPlayerIndex,
        uint256 defenderPlayerIndex,
        uint32 basePower,
        uint32 accuracy, // out of 100
        uint256 volatility,
        Type attackType,
        MoveClass attackSupertype,
        uint256 rng,
        uint256 critRate // out of 100
    ) internal view returns (int32, EngineEventType) {
        // Do accuracy check first to decide whether or not to short circuit
        // [0... accuracy] [accuracy + 1, ..., 100]
        // [succeeds     ] [fails                 ]
        if ((rng % 100) >= accuracy) {
            return (0, EngineEventType.MoveMiss);
        }
        uint256[] memory monIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
        int32 damage;
        EngineEventType eventType = EngineEventType.None;
        {
            uint32 attackStat;
            uint32 defenceStat;

            // Grab the right atk/defense stats, and apply the delta if needed
            if (attackSupertype == MoveClass.Physical) {
                attackStat = uint32(
                    int32(
                        ENGINE.getMonValueForBattle(
                            battleKey, attackerPlayerIndex, monIndex[attackerPlayerIndex], MonStateIndexName.Attack
                        )
                    )
                    + ENGINE.getMonStateForBattle(
                        battleKey, attackerPlayerIndex, monIndex[attackerPlayerIndex], MonStateIndexName.Attack
                    )
                );
                defenceStat = uint32(
                    int32(
                        ENGINE.getMonValueForBattle(
                            battleKey, defenderPlayerIndex, monIndex[defenderPlayerIndex], MonStateIndexName.Defense
                        )
                    )
                    + ENGINE.getMonStateForBattle(
                        battleKey, defenderPlayerIndex, monIndex[defenderPlayerIndex], MonStateIndexName.Defense
                    )
                );
            } else {
                attackStat = uint32(
                    int32(
                        ENGINE.getMonValueForBattle(
                            battleKey,
                            attackerPlayerIndex,
                            monIndex[attackerPlayerIndex],
                            MonStateIndexName.SpecialAttack
                        )
                    )
                    + ENGINE.getMonStateForBattle(
                        battleKey, attackerPlayerIndex, monIndex[attackerPlayerIndex], MonStateIndexName.SpecialAttack
                    )
                );
                defenceStat = uint32(
                    int32(
                        ENGINE.getMonValueForBattle(
                            battleKey,
                            defenderPlayerIndex,
                            monIndex[defenderPlayerIndex],
                            MonStateIndexName.SpecialDefense
                        )
                    )
                    + ENGINE.getMonStateForBattle(
                        battleKey, defenderPlayerIndex, monIndex[defenderPlayerIndex], MonStateIndexName.SpecialDefense
                    )
                );
            }

            // Prevent weird stat bugs from messing up the math
            if (attackStat <= 0) {
                attackStat = 1;
            }
            if (defenceStat <= 0) {
                defenceStat = 1;
            }

            uint32 scaledBasePower;
            {
                scaledBasePower = TYPE_CALCULATOR.getTypeEffectiveness(
                    attackType,
                    Type(
                        ENGINE.getMonValueForBattle(
                            battleKey, defenderPlayerIndex, monIndex[defenderPlayerIndex], MonStateIndexName.Type1
                        )
                    ),
                    basePower
                );
                Type defenderType2 = Type(
                    ENGINE.getMonValueForBattle(
                        battleKey, defenderPlayerIndex, monIndex[defenderPlayerIndex], MonStateIndexName.Type2
                    )
                );
                if (defenderType2 != Type.None) {
                    scaledBasePower = TYPE_CALCULATOR.getTypeEffectiveness(attackType, defenderType2, scaledBasePower);
                }
            }

            // Calculate move volatility
            // Check if rng flag is even or odd
            // Either way, take half the value use it as the scaling factor
            uint256 rng2 = uint256(keccak256(abi.encode(rng)));
            uint32 rngScaling = 100;
            if (volatility > 0) {
                // We scale up
                if (rng2 % 100 > 50) {
                    rngScaling = 100 + uint32(rng2 % (volatility + 1));
                }
                // We scale down
                else {
                    rngScaling = 100 - uint32(rng2 % (volatility + 1));
                }
            }

            // Calculate crit chance (in order to avoid correlating effect chance w/ crit chance, we use a new rng)
            // [0... crit rate] [crit rate + 1, ..., 100]
            // [succeeds      ] [fails                  ]
            uint256 rng3 = uint256(keccak256(abi.encode(rng2)));
            uint32 critNum = 1;
            uint32 critDenom = 1;
            if ((rng3 % 100) <= critRate) {
                critNum = CRIT_NUM;
                critDenom = CRIT_DENOM;
                eventType = EngineEventType.MoveCrit;
            }
            damage = int32(
                critNum * (scaledBasePower * attackStat * rngScaling) / (defenceStat * RNG_SCALING_DENOM * critDenom)
            );
        }
        return (damage, eventType);
    }
}
