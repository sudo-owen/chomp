// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";

import {StatusEffect} from "./StatusEffect.sol";

contract ZapStatus is StatusEffect {
    
    uint8 private constant ALREADY_SKIPPED = 1;

    constructor(IEngine engine) StatusEffect(engine) {}

    function name() public pure override returns (string memory) {
        return "Zap";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return (r == EffectStep.OnApply || r == EffectStep.RoundStart || r == EffectStep.RoundEnd
                || r == EffectStep.OnRemove || r == EffectStep.OnMonSwitchIn);
    }

    function onApply(uint256 rng, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Get the battle key and compute priority player index
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 priorityPlayerIndex = ENGINE.computePriorityPlayerIndex(battleKey, rng);

        uint8 state;

        // Check if opponent has yet to move
        if (targetIndex != priorityPlayerIndex) {
            // Opponent hasn't moved yet (they're the non-priority player)
            // Set skip turn flag immediately
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
            state = ALREADY_SKIPPED; // Ready to remove at RoundEnd
        }
        // else: Opponent has already moved, state = 0 (not yet skipped), wait for RoundStart

        return (abi.encode(state), false);
    }

    function onRoundStart(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // If we're at RoundStart and effect is still present, always set skip flag and mark as skipped
        // (If state was ALREADY_SKIPPED, effect would have been removed at previous RoundEnd)
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
        return (abi.encode(ALREADY_SKIPPED), false);
    }

    function onMonSwitchIn(uint256, bytes memory extraData, uint256, uint256)
        external
        override
        pure
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        return (extraData, false);
    }

    function onRemove(bytes memory data, uint256 targetIndex, uint256 monIndex) public override {
        super.onRemove(data, targetIndex, monIndex);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        public
        pure
        override
        returns (bytes memory, bool)
    {
        uint8 state = abi.decode(extraData, (uint8));

        // Remove the effect if we've already set the skip flag and it's been processed
        if (state == ALREADY_SKIPPED) {
            return (extraData, true);
        }

        // Otherwise keep the effect
        return (extraData, false);
    }
}