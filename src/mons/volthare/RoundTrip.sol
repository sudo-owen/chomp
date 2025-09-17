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

contract RoundTrip is StandardAttack {
    constructor(IEngine ENGINE, ITypeCalculator TYPE_CALCULATOR)
        StandardAttack(
            address(msg.sender),
            ENGINE,
            TYPE_CALCULATOR,
            ATTACK_PARAMS({
                NAME: "Round Trip",
                BASE_POWER: 30,
                STAMINA_COST: 1,
                ACCURACY: 100,
                MOVE_TYPE: Type.Lightning,
                MOVE_CLASS: MoveClass.Special,
                PRIORITY: DEFAULT_PRIORITY,
                CRIT_RATE: DEFAULT_CRIT_RATE,
                VOLATILITY: DEFAULT_VOL,
                EFFECT_ACCURACY: 0,
                EFFECT: IEffect(address(0))
            })
        )
    {}

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata extraData, uint256 rng)
        public
        override
        returns (bytes memory)
    {
        // Deal the damage
        bytes memory moveReturnData = super.move(battleKey, attackerPlayerIndex, extraData, rng);

        // We're guaranteed that StandardAttack returns the damage
        (int32 damage) = abi.decode(moveReturnData, (int32));

        if (damage > 0) {
            // Decode the swap index from extraData and swap the active mon
            (uint256 swapIndex) = abi.decode(extraData, (uint256));
            ENGINE.switchActiveMon(attackerPlayerIndex, swapIndex);
        }

        return moveReturnData;
    }

    function extraDataType() external pure override returns (ExtraDataType) {
        return ExtraDataType.SelfTeamIndex;
    }
}
