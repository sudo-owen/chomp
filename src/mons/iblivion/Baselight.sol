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
 * - Gains 1 stack at the end of each turn (except turn 0), up to a max of 3
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

    // Key for storing whether the mon has ever switched in (to track first switch-in)
    function _hasActivatedKey(uint256 playerIndex, uint256 monIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, monIndex, "BaselightHasActivated"));
    }

    // Key for storing the Baselight level
    function _baselightKey(uint256 playerIndex, uint256 monIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, monIndex, "BaselightLevel"));
    }

    function getBaselightLevel(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) public view returns (uint256) {
        return uint256(ENGINE.getGlobalKV(battleKey, _baselightKey(playerIndex, monIndex)));
    }

    function setBaselightLevel(uint256 playerIndex, uint256 monIndex, uint256 level) public {
        if (level > MAX_BASELIGHT_LEVEL) {
            level = MAX_BASELIGHT_LEVEL;
        }
        ENGINE.setGlobalKV(_baselightKey(playerIndex, monIndex), uint192(level));
    }

    function decreaseBaselightLevel(uint256 playerIndex, uint256 monIndex, uint256 amount) public {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 currentLevel = getBaselightLevel(battleKey, playerIndex, monIndex);
        if (amount >= currentLevel) {
            ENGINE.setGlobalKV(_baselightKey(playerIndex, monIndex), uint192(0));
        } else {
            ENGINE.setGlobalKV(_baselightKey(playerIndex, monIndex), uint192(currentLevel - amount));
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

        // Check if this is the first time switching in this game
        uint192 hasActivated = ENGINE.getGlobalKV(battleKey, _hasActivatedKey(playerIndex, monIndex));
        if (hasActivated == 0) {
            // First switch-in: set Baselight level to 1
            ENGINE.setGlobalKV(_baselightKey(playerIndex, monIndex), uint192(INITIAL_BASELIGHT_LEVEL));
            ENGINE.setGlobalKV(_hasActivatedKey(playerIndex, monIndex), uint192(1));
        }

        // Add the effect to track round ends
        // Use extraData = 1 to skip the first round end (turn 0)
        ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), bytes32(uint256(1)));
    }

    // IEffect implementation - should run at end of round
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.RoundEnd);
    }

    function onRoundEnd(uint256, bytes32 extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes32 updatedExtraData, bool removeAfterRun)
    {
        // Skip increment on turn 0 (when extraData == 1)
        if (uint256(extraData) == 1) {
            return (bytes32(uint256(0)), false);
        }

        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 currentLevel = getBaselightLevel(battleKey, targetIndex, monIndex);
        if (currentLevel < MAX_BASELIGHT_LEVEL) {
            ENGINE.setGlobalKV(_baselightKey(targetIndex, monIndex), uint192(currentLevel + 1));
        }
        return (extraData, false);
    }
}
