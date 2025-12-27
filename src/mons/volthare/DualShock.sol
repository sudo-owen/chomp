// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {StandardAttack} from "../../moves/StandardAttack.sol";
import {ATTACK_PARAMS} from "../../moves/StandardAttackStructs.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";
import {Overload} from "../../effects/battlefield/Overload.sol";

contract DualShock is StandardAttack {

    IEffect immutable ZAP_STATUS;
    Overload immutable OVERLOAD;

    constructor(IEngine ENGINE, ITypeCalculator TYPE_CALCULATOR, IEffect _ZAP_STATUS, Overload _OVERLOAD)
        StandardAttack(
            address(msg.sender),
            ENGINE,
            TYPE_CALCULATOR,
            ATTACK_PARAMS({
                NAME: "Dual Shock",
                BASE_POWER: 60,
                STAMINA_COST: 0,
                ACCURACY: 100,
                MOVE_TYPE: Type.Cyber,
                MOVE_CLASS: MoveClass.Special,
                PRIORITY: DEFAULT_PRIORITY,
                CRIT_RATE: DEFAULT_CRIT_RATE,
                VOLATILITY: DEFAULT_VOL,
                EFFECT_ACCURACY: 0,
                EFFECT: IEffect(address(0))
            })
        )
    {
        ZAP_STATUS = _ZAP_STATUS;
        OVERLOAD = _OVERLOAD;
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, uint240 extraData, uint256 rng)
        public
        override
    {
        // Deal the damage
        super.move(battleKey, attackerPlayerIndex, extraData, rng);

        // Apply Zap to self
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
        ENGINE.addEffect(attackerPlayerIndex, activeMonIndex, ZAP_STATUS, "");

        // Apply Overload to self
        OVERLOAD.applyOverload(attackerPlayerIndex);
    }
}
