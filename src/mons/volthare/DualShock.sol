// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";

import {IEffect} from "../../effects/IEffect.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {StandardAttack} from "../../moves/StandardAttack.sol";
import {ATTACK_PARAMS} from "../../moves/StandardAttackStructs.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract DualShock is StandardAttack {
    
    constructor(IEngine ENGINE, ITypeCalculator TYPE_CALCULATOR, IEffect ZAP_STATUS)
        StandardAttack(
            address(msg.sender),
            ENGINE,
            TYPE_CALCULATOR,
            ATTACK_PARAMS({
                NAME: "Dual Shock",
                BASE_POWER: 60,
                STAMINA_COST: 0,
                ACCURACY: 100,
                MOVE_TYPE: Type.Lightning,
                MOVE_CLASS: MoveClass.Special,
                PRIORITY: DEFAULT_PRIORITY,
                CRIT_RATE: DEFAULT_CRIT_RATE,
                VOLATILITY: DEFAULT_VOL,
                EFFECT_ACCURACY: 0,
                EFFECT: IEffect(ZAP_STATUS)
            })
        )
    {}

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata extraData, uint256 rng)
        public
        override
    {
        // Deal the damage
        super.move(battleKey, attackerPlayerIndex, extraData, rng);

        // Inflict Zap on self
        ENGINE.addEffect(attackerPlayerIndex, ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex], effect(battleKey), "");
    }
}
