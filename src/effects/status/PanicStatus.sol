// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IEffect} from "../IEffect.sol";

import {StatusEffect} from "./StatusEffect.sol";

contract PanicStatus is StatusEffect {
    uint256 constant DURATION = 3;

    constructor(IEngine engine) StatusEffect(engine) {}

    function name() public pure override returns (string memory) {
        return "Panic";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        // Need to also return OnRemove to remove the global status flag
        return r == EffectStep.RoundStart || r == EffectStep.RoundEnd || r == EffectStep.OnApply
            || r == EffectStep.OnRemove;
    }

    // At the start of the turn, check to see if we should apply fright or end early
    function onRoundStart(uint256 rng, bytes memory extraData, uint256, uint256)
        external
        pure
        override
        returns (bytes memory, bool)
    {
        bool wakeEarly = rng % 3 == 0;
        if (wakeEarly) {
            return (extraData, true);
        }
        return (extraData, false);
    }

    // On apply, checks to apply the fright flag, and then sets the extraData to be the duration
    function onApply(uint256, bytes memory, uint256, uint256)
        external
        pure
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        return (abi.encode(DURATION), false);
    }

    // Apply fright on end of turn, and then check how many turns are left
    function onRoundEnd(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool removeAfterRun)
    {
        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Get current stamina delta of the target mon
        int32 staminaDelta = ENGINE.getMonStateForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Stamina);

        // If the stamina is less than the max stamina, then reduce stamina by 1 (as long as it's not already 0)
        uint32 maxStamina = ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Stamina);
        if (staminaDelta + int32(maxStamina) > 0) {
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.Stamina, -1);
        }

        uint256 turnsLeft = abi.decode(extraData, (uint256));
        if (turnsLeft == 1) {
            return (extraData, true);
        } else {
            return (abi.encode(turnsLeft - 1), false);
        }
    }
}
