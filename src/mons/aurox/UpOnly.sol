// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {EffectStep} from "../../Enums.sol";
import {MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {StatBoosts, StatBoostType, StatBoostFlag} from "../../effects/StatBoosts.sol";

contract UpOnly is IAbility, BasicEffect {
    int32 public constant ATTACK_BOOST_PERCENT = 5; // 5% attack boost per hit

    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        STAT_BOOSTS = _STAT_BOOSTS;
    }

    // IAbility implementation
    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Up Only";
    }

    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Check if the effect has already been set for this mon
        bytes32 monEffectId = keccak256(abi.encode(playerIndex, monIndex, name()));
        if (ENGINE.getGlobalKV(battleKey, monEffectId) != bytes32(0)) {
            return;
        }
        // Otherwise, add this effect to the mon when it switches in
        else {
            uint256 value = 1;
            ENGINE.setGlobalKV(monEffectId, bytes32(value));
            ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), "");
        }
    }

    // IEffect implementation
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.AfterDamage);
    }

    function onAfterDamage(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex, int32)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Add 5% attack boost every time damage is taken
        STAT_BOOSTS.addStatBoost(
            targetIndex,
            monIndex,
            uint256(MonStateIndexName.Attack),
            ATTACK_BOOST_PERCENT,
            StatBoostType.Multiply,
            StatBoostFlag.Perm
        );

        return (extraData, false);
    }
}
