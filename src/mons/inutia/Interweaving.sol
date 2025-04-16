// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {StatBoosts} from "../../effects/StatBoosts.sol";

contract Interweaving is IAbility, BasicEffect {
    int32 constant DECREASE_PERCENTAGE = 10;
    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOST;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOST) {
        ENGINE = _ENGINE;
        STAT_BOOST = _STAT_BOOST;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Interweaving";
    }

    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Lower opposing mon Attack stat
        uint256 otherPlayerIndex = (playerIndex + 1) % 2;
        uint256 otherPlayerActiveMonIndex =
            ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[otherPlayerIndex];
        STAT_BOOST.addStatBoost(
            otherPlayerIndex,
            otherPlayerActiveMonIndex,
            uint256(MonStateIndexName.Attack),
            DECREASE_PERCENTAGE,
            StatBoostType.Divide,
            StatBoostFlag.Temp
        );

        // Check if the effect has already been set for this mon
        bytes32 monEffectId = keccak256(abi.encode(playerIndex, monIndex, name()));
        if (ENGINE.getGlobalKV(battleKey, monEffectId) != bytes32(0)) {
            return;
        }
        // Otherwise, add this effect to the mon when it switches in
        // This way we can trigger on switch out
        else {
            uint256 value = 1;
            ENGINE.setGlobalKV(monEffectId, bytes32(value));
            ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), abi.encode(0));
        }
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.OnMonSwitchOut || step == EffectStep.OnApply);
    }

    function onMonSwitchOut(uint256, bytes memory, uint256 targetIndex, uint256)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint256 otherPlayerIndex = (targetIndex + 1) % 2;
        uint256 otherPlayerActiveMonIndex =
            ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[otherPlayerIndex];
        STAT_BOOST.addStatBoost(
            otherPlayerIndex,
            otherPlayerActiveMonIndex,
            uint256(MonStateIndexName.SpecialAttack),
            DECREASE_PERCENTAGE,
            StatBoostType.Divide,
            StatBoostFlag.Temp
        );
        return ("", false);
    }
}
