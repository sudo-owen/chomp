// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {NO_OP_MOVE_INDEX} from "../../Constants.sol";
import {EffectStep} from "../../Enums.sol";
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

    function _globalSleepKey(uint256 targetIndex) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(name(), targetIndex));
    }

    // Whether or not to add the effect if the step condition is met
    function shouldApply(bytes memory data, uint256 targetIndex, uint256 monIndex) public view override returns (bool) {
        bool shouldApplyStatusInGeneral = super.shouldApply(data, targetIndex, monIndex);
        bool playerHasZeroSleepers =
                address(bytes20(ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), _globalSleepKey(targetIndex)))) == address(0);
        return (shouldApplyStatusInGeneral && playerHasZeroSleepers);
    }

    function _applySleep(uint256 targetIndex, uint256 monIndex) internal {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        ENGINE.setMove(battleKey, targetIndex, NO_OP_MOVE_INDEX, "", "");
    }

    // At the start of the turn, check to see if we should apply sleep or end early
    function onRoundStart(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        bool wakeEarly = rng % 3 == 0;
        if (!wakeEarly) {
            _applySleep(targetIndex, monIndex);
        }
        return (extraData, wakeEarly);
    }

    // On apply, checks to apply the sleep flag, and then sets the extraData to be the duration
    function onApply(uint256 rng, bytes memory data, uint256 targetIndex, uint256 monIndex)
        public
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        super.onApply(rng, data, targetIndex, monIndex);
        // Check if opponent has yet to move and if so, also affect their move for this round
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 priorityPlayerIndex = ENGINE.computePriorityPlayerIndex(battleKey, rng);
        if (targetIndex != priorityPlayerIndex) {
            _applySleep(targetIndex, monIndex);
        }
        return (abi.encode(DURATION), false);
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


    function onRemove(bytes memory extraData, uint256 targetIndex, uint256 monIndex) public override {
        super.onRemove(extraData, targetIndex, monIndex);
        ENGINE.setGlobalKV(_globalSleepKey(targetIndex), bytes32(0));
    }
}
