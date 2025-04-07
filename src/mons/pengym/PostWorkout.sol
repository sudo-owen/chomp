// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Structs.sol";
import {NO_OP_MOVE_INDEX} from "../../Constants.sol";
import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {StatBoost} from "../../effects/StatBoost.sol";

import {StatusEffectLib} from "../../effects/status/StatusEffectLib.sol";

contract PostWorkout is IAbility, BasicEffect {

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Post-Workout";
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
            ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), abi.encode(0));
        }
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.OnMonSwitchOut);
    }

    function onMonSwitchOut(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        bytes32 keyForMon = StatusEffectLib.getKeyForMonIndex(targetIndex, monIndex);
        bytes32 statusAddress = ENGINE.getGlobalKV(battleKey, keyForMon);

        // Check if a status exists
        if (statusAddress != bytes32(0)) {
            IEffect statusEffect = IEffect(address(uint160(uint256(statusAddress))));

            // Get the index of the effect and remove it
            uint256 effectIndex;
            (IEffect[] memory effects,) = ENGINE.getEffects(battleKey, targetIndex, monIndex);
            for (uint i; i < effects.length; i++) {
                if (effects[i] == statusEffect) {
                    effectIndex = i;
                    break;
                }
            }
            ENGINE.removeEffect(targetIndex, monIndex, effectIndex);

            // Boost stamina by 1
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.Stamina, 1);
        }
        return ("", false);
    }
}