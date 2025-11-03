// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {StatBoosts} from "../../effects/StatBoosts.sol";
import {Baselight} from "../iblivion/Baselight.sol";

contract IntrinsicValue is IAbility, BasicEffect {
    IEngine immutable ENGINE;
    Baselight immutable BASELIGHT;
    StatBoosts immutable STAT_BOOST;

    constructor(IEngine _ENGINE, Baselight _BASELIGHT, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        BASELIGHT = _BASELIGHT;
        STAT_BOOST = _STAT_BOOSTS;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Intrinsic Value";
    }

    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Check if the effect has already been set for this mon
        (IEffect[] memory effects,) = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(this)) {
                return;
            }
        }
        ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), abi.encode(0));
    }

    // Should run at end of round
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.RoundEnd);
    }

    function onRoundEnd(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        bool statsReset = false;

        // Check for stat boosts in ATK/DEF/SpATK/SpDEF/SPD:
        uint256[] memory statIndexNames = new uint256[](5);
        statIndexNames[0] = uint256(MonStateIndexName.Attack);
        statIndexNames[1] = uint256(MonStateIndexName.Defense);
        statIndexNames[2] = uint256(MonStateIndexName.SpecialAttack);
        statIndexNames[3] = uint256(MonStateIndexName.SpecialDefense);
        statIndexNames[4] = uint256(MonStateIndexName.Speed);
        for (uint256 i = 0; i < statIndexNames.length; i++) {
            // bool reset = STAT_BOOST.clearTempBoost(targetIndex, monIndex, statIndexNames[i]);
            // statsReset = statsReset || reset;
        }
        if (statsReset) {
            // Increase baselight level if we reset any stats
            BASELIGHT.increaseBaselightLevel(targetIndex, monIndex);
        }
        return ("", false);
    }
}
