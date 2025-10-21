// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {EffectStep} from "../../Enums.sol";

import {MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";

import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";

contract Angery is IAbility, BasicEffect {
    uint256 public constant CHARGE_COUNT = 3; // After 3 charges, consume all charges to heal
    int32 public constant MAX_HP_DENOM = 6; // Heal for 1/6 of HP

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    // IAbility implementation
    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Angery";
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

    // IEffect implementation
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.RoundEnd || step == EffectStep.AfterDamage);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint256 numCharges = abi.decode(extraData, (uint256));
        if (numCharges == CHARGE_COUNT) {
            // Heal
            int32 healAmount =
                int32(
                    ENGINE.getMonValueForBattle(ENGINE.battleKeyForWrite(), targetIndex, monIndex, MonStateIndexName.Hp)
                ) / MAX_HP_DENOM;
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.Hp, healAmount);
            // Reset the charges
            return (abi.encode(numCharges - CHARGE_COUNT), false);
        } else {
            return (extraData, false);
        }
    }

    function onAfterDamage(uint256, bytes memory extraData, uint256, uint256, int32)
        external
        pure
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint256 numCharges = abi.decode(extraData, (uint256));
        return (abi.encode(numCharges + 1), false);
    }
}
