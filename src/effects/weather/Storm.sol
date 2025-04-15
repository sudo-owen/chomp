// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../Enums.sol";
import "../../Structs.sol";

import {IEngine} from "../../IEngine.sol";
import {BasicEffect} from "../BasicEffect.sol";
import {IEffect} from "../IEffect.sol";
import {StatBoosts} from "../StatBoosts.sol";

contract Storm is BasicEffect {

    uint256 public constant DEFAULT_DURATION = 3;

    int32 public constant SPEED_PERCENT = 25;
    int32 public constant SP_DEF_PERCENT = 25;

    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOST;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOST) {
        ENGINE = _ENGINE;
        STAT_BOOST = _STAT_BOOST;
    }
    
    function name() public pure override returns (string memory) {
        return "Stormy Weather";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return (
            r == EffectStep.OnApply || 
            r == EffectStep.RoundEnd ||
            r == EffectStep.OnMonSwitchIn ||
            r == EffectStep.OnRemove
        );
    }

    function _effectKey(uint256 playerIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, name()));
    }

    function applyStorm(uint256 playerIndex) public {
        // Check if we have an active Storm effect
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 duration = getDuration(battleKey, playerIndex);
        if (duration == 0) {
            // If not, add the effect to the global effects array
            ENGINE.addEffect(2, 0, IEffect(address(this)), abi.encode(playerIndex));
        } else {
            // Otherwise, reset the duration
            setDuration(DEFAULT_DURATION, playerIndex);
        }
    }

    function getDuration(bytes32 battleKey, uint256 playerIndex) public view returns (uint256) {
        return uint256(ENGINE.getGlobalKV(battleKey, _effectKey(playerIndex)));
    }

    function setDuration(uint256 newDuration, uint256 playerIndex) public {
        ENGINE.setGlobalKV(_effectKey(playerIndex), bytes32(newDuration));
    }

    function _applyStatChange(uint256 playerIndex, uint256 monIndex) internal {
        // Apply stat boosts (speed buff / sp def debuff)
        STAT_BOOST.addStatBoost(playerIndex, monIndex, uint256(MonStateIndexName.Speed), SPEED_PERCENT, StatBoostType.Multiply, StatBoostFlag.Temp);
        STAT_BOOST.addStatBoost(playerIndex, monIndex, uint256(MonStateIndexName.SpecialDefense), SP_DEF_PERCENT, StatBoostType.Divide, StatBoostFlag.Temp);
    }

    function _removeStatChange(uint256 playerIndex, uint256 monIndex) internal {
        // Reset stat boosts (speed buff / sp def debuff)
        STAT_BOOST.removeStatBoost(playerIndex, monIndex, uint256(MonStateIndexName.Speed), SPEED_PERCENT, StatBoostType.Multiply, StatBoostFlag.Temp);
        STAT_BOOST.removeStatBoost(playerIndex, monIndex, uint256(MonStateIndexName.SpecialDefense), SP_DEF_PERCENT, StatBoostType.Divide, StatBoostFlag.Temp);
    }

    function onApply(uint256, bytes memory extraData, uint256, uint256)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint256 playerIndex = abi.decode(extraData, (uint256));

        // Set default duration
        setDuration(DEFAULT_DURATION, playerIndex);

        // Apply stat change to the team of the player who summoned Storm
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[playerIndex];
        _applyStatChange(playerIndex, activeMonIndex);

        return (extraData, false);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        uint256 playerIndex = abi.decode(extraData, (uint256));
        uint256 duration = getDuration(ENGINE.battleKeyForWrite(), playerIndex);
        if (duration == 1) {
            return (extraData, true);
        } else {
            setDuration(duration - 1, playerIndex);
            return (extraData, false);
        }
    }

    function onMonSwitchIn(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex) external override returns (bytes memory updatedExtraData, bool removeAfterRun) {
        uint256 playerIndex = abi.decode(extraData, (uint256));
        // Apply stat change to the mon on the team of the player who summoned Storm
        if (targetIndex == playerIndex) {
            _applyStatChange(targetIndex, monIndex);
        }
        return (extraData, false);
    }

    function onRemove(bytes memory extraData, uint256, uint256) external override {
        uint256 playerIndex = abi.decode(extraData, (uint256));
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[playerIndex];
        // Reset stat changes from the mon on the team of the player who summoned Storm
        _removeStatChange(playerIndex, activeMonIndex);
        // Clear the duration when we clear the effect
        setDuration(0, playerIndex);
    }
}
