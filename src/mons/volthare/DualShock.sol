// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {StandardAttack} from "../../moves/StandardAttack.sol";
import {ATTACK_PARAMS} from "../../moves/StandardAttackStructs.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract DualShock is StandardAttack, BasicEffect {
    
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

    function name() public pure override(StandardAttack, BasicEffect) returns (string memory) {
        return "Dual Shock";
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata extraData, uint256 rng)
        public
        override
    {
        // Deal the damage
        super.move(battleKey, attackerPlayerIndex, extraData, rng);

        // Apply effect to self
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
        ENGINE.addEffect(attackerPlayerIndex, activeMonIndex, this, "");
    }

    // Effect implementation
    
    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return r == EffectStep.RoundEnd;
    }

    function onRoundEnd(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Apply Zap to self
        ENGINE.addEffect(targetIndex, monIndex, effect(ENGINE.battleKeyForWrite()), "");

        return ("", true);
    }
}
