// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";

import {StatusEffect} from "./StatusEffect.sol";

contract SleepStatus is StatusEffect {
    uint256 constant DURATION = 3;

    constructor(IEngine engine) StatusEffect(engine) {}

    function name() public pure override returns (string memory) {
        return "Sleep";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return
            r == EffectStep.RoundStart || r == EffectStep.RoundEnd || r == EffectStep.OnApply
                || r == EffectStep.OnRemove;
    }

    // At the start of the turn, check to see if we should apply sleep or end early
    function onRoundStart(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        bool wakeEarly = rng % 3 == 0;
        if (wakeEarly) {
            return (extraData, true);
        } else {
            _applySleep(rng, targetIndex, monIndex);
        }
        return (extraData, false);
    }

    // On apply, checks to apply the sleep flag, and then sets the extraData to be the duration
    function onApply(uint256 rng, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        _applySleep(rng, targetIndex, monIndex);
        return (abi.encode(DURATION), false);
    }

    // Sleep just skips the turn
    function _applySleep(uint256, uint256 targetIndex, uint256 monIndex) internal {
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        external
        pure
        override
        returns (bytes memory, bool removeAfterRun)
    {
        uint256 turnsLeft = abi.decode(extraData, (uint256));
        if (turnsLeft == 1) {
            return (extraData, true);
        } else {
            return (abi.encode(turnsLeft - 1), false);
        }
    }

    function _globalSleepKey(uint256 targetIndex) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(name(), targetIndex));
    }

    // Whether or not to add the effect if the step condition is met
    function shouldApply(bytes memory data, uint256 targetIndex, uint256 monIndex) public override returns (bool) {
        bool shouldApplyStatusInGeneral = super.shouldApply(data, targetIndex, monIndex);
        if (!shouldApplyStatusInGeneral) {
            return false;
        } else {
            // Get value from ENGINE KV
            bytes32 globalSleepValueForPlayer =
                ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), _globalSleepKey(targetIndex));

            // Check if sleep already exists for the team
            if (globalSleepValueForPlayer == bytes32(0)) {
                // If not, set the flag and return true
                ENGINE.setGlobalKV(_globalSleepKey(targetIndex), bytes32("1"));
                return true;
            } else {
                // Otherwise return false (we can only have one instance of sleep)
                return false;
            }
        }
    }

    // Remove sleep flag
    function _removeSleep(uint256 targetIndex, uint256 monIndex) internal {
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 0);
    }

    function onRemove(bytes memory extraData, uint256 targetIndex, uint256 monIndex) public override {
        // Remove any outstanding sleep flags (e.g. if turn X we got sleep, then turn X+1 we wake up, then we should remove the flag)
        _removeSleep(targetIndex, monIndex);

        // Call the super onRemove and then remove the extra flag sleep clause we set as well
        super.onRemove(extraData, targetIndex, monIndex);
        ENGINE.setGlobalKV(_globalSleepKey(targetIndex), bytes32(0));
    }
}
