// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";

import {StatusEffect} from "./StatusEffect.sol";

contract ZapStatus is StatusEffect {
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
        uint256 priorityPlayerIndex = ENGINE.getPriorityPlayerIndex(battleKey, rng);

        // State: 0 = waiting for RoundStart, 1 = ready to remove at RoundEnd
        uint8 state;

        // Check if opponent has yet to move
        if (targetIndex != priorityPlayerIndex) {
            // Opponent hasn't moved yet (they're the non-priority player)
            // Set skip turn flag immediately
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
            state = 1; // Ready to remove at RoundEnd
        } else {
            // Opponent has already moved (they're the priority player)
            // Don't set skip flag yet, wait for RoundStart
            state = 0; // Waiting for RoundStart
        }

        return (abi.encode(state), false);
    }

    function onRoundStart(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint8 state = abi.decode(extraData, (uint8));

        if (state == 0) {
            // Set skip turn flag now
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
            state = 1; // Ready to remove at RoundEnd
        }

        return (abi.encode(state), false);
    }

    function onMonSwitchIn(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint8 state = abi.decode(extraData, (uint8));

        if (state == 0) {
            // Set skip turn flag when switching in
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);
            state = 1; // Ready to remove at RoundEnd
        }

        return (abi.encode(state), false);
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

        // Remove the effect if we've already set the skip flag
        if (state == 1) {
            return (extraData, true);
        }

        // Otherwise keep the effect
        return (extraData, false);
    }
}
