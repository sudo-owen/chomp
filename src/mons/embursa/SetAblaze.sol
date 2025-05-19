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
import {HeatBeaconLib} from "./HeatBeaconLib.sol";

contract SetAblaze is StandardAttack {
    constructor(IEngine ENGINE, ITypeCalculator TYPE_CALCULATOR, IEffect BURN_STATUS)
        StandardAttack(
            address(msg.sender),
            ENGINE,
            TYPE_CALCULATOR,
            ATTACK_PARAMS({
                NAME: "Set Ablaze",
                BASE_POWER: 90,
                STAMINA_COST: 3,
                ACCURACY: 100,
                MOVE_TYPE: Type.Fire,
                MOVE_CLASS: MoveClass.Special,
                PRIORITY: DEFAULT_PRIORITY,
                CRIT_RATE: DEFAULT_CRIT_RATE,
                VOLATILITY: DEFAULT_VOL,
                EFFECT_ACCURACY: 30,
                EFFECT: BURN_STATUS
            })
        )
    {}

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata args, uint256 rng) public override {
        super.move(battleKey, attackerPlayerIndex, args, rng);
        // Clear the priority boost
        if (HeatBeaconLib.getPriorityBoost(ENGINE, attackerPlayerIndex) == 1) {
            HeatBeaconLib.clearPriorityBoost(ENGINE, attackerPlayerIndex);
        }
    }

    function priority(bytes32, uint256 attackerPlayerIndex) public view override returns (uint32) {
        return DEFAULT_PRIORITY + HeatBeaconLib.getPriorityBoost(ENGINE, attackerPlayerIndex);
    }
}
