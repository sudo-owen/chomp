// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {EffectStep} from "../../Enums.sol";
import {EffectInstance} from "../../Structs.sol";
import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";

/**
 * Baselight Ability for Iblivion
 * - Starts at 1 stack when the mon first switches in (only on first switch-in of the game)
 * - Gains 1 stack at the end of each turn, up to a max of 3
 * - Level is stored in the effect's extraData
 */
contract Baselight is IAbility, BasicEffect {
    uint256 public constant MAX_BASELIGHT_LEVEL = 3;
    uint256 public constant INITIAL_BASELIGHT_LEVEL = 1;

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Baselight";
    }

    function getBaselightLevel(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) public view returns (uint256) {
        (EffectInstance[] memory effects,) = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                return uint256(effects[i].data);
            }
        }
        return 0;
    }

    function setBaselightLevel(uint256 playerIndex, uint256 monIndex, uint256 level) public {
        if (level > MAX_BASELIGHT_LEVEL) {
            level = MAX_BASELIGHT_LEVEL;
        }
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                ENGINE.editEffect(playerIndex, monIndex, indices[i], bytes32(level));
                return;
            }
        }
    }

    function decreaseBaselightLevel(uint256 playerIndex, uint256 monIndex, uint256 amount) public {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                uint256 currentLevel = uint256(effects[i].data);
                uint256 newLevel = amount >= currentLevel ? 0 : currentLevel - amount;
                ENGINE.editEffect(playerIndex, monIndex, indices[i], bytes32(newLevel));
                return;
            }
        }
    }

    // IAbility implementation - called when the mon switches in
    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Check if the effect has already been set for this mon
        (EffectInstance[] memory effects,) = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                return;
            }
        }

        // First switch-in: add effect with initial Baselight level stored in extraData
        ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), bytes32(uint256(INITIAL_BASELIGHT_LEVEL)));
    }

    // IEffect implementation - should run at end of round
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.RoundEnd);
    }

    function onRoundEnd(uint256, bytes32 extraData, uint256, uint256)
        external
        pure
        override
        returns (bytes32 updatedExtraData, bool removeAfterRun)
    {
        uint256 currentLevel = uint256(extraData);
        if (currentLevel < MAX_BASELIGHT_LEVEL) {
            return (bytes32(currentLevel + 1), false);
        }
        return (extraData, false);
    }
}
