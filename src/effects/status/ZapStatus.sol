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
        return (r == EffectStep.OnApply || r == EffectStep.RoundEnd || r == EffectStep.OnRemove || r == EffectStep.OnMonSwitchIn);
    }

    function onApply(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Set skip turn flag
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);

        // Do not update data or remove
        return (extraData, false);
    }

    function onMonSwitchIn(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {   
        // Set skip turn flag
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.ShouldSkipTurn, 1);

        // Do not update data or remove
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
        // Remove the effect
        return (extraData, true);
    }
}
