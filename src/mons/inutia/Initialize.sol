// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {StatBoosts} from "../../effects/StatBoosts.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";

contract Initialize is IMoveSet, BasicEffect {

    int32 public constant ATTACK_BUFF_PERCENT = 50;
    int32 public constant SP_ATTACK_BUFF_PERCENT = 50;

    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        STAT_BOOSTS = _STAT_BOOSTS;
    }

    function name() public pure override(IMoveSet, BasicEffect) returns (string memory) {
        return "Initialize";
    }

    function _initializeKey(uint256 playerIndex, uint256 monIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, monIndex, name()));
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
        // Check if global KV is set
        bytes32 flag = ENGINE.getGlobalKV(battleKey, _initializeKey(attackerPlayerIndex, activeMonIndex));
        if (flag == bytes32(0)) {
            // Apply the buffs
            _applyBuff(attackerPlayerIndex, activeMonIndex);
            
            // Apply effect globally
            ENGINE.addEffect(2, 2, this, _encodeState(attackerPlayerIndex, activeMonIndex));
            // Set global KV to prevent this move doing anything until Inutia swaps out
            uint256 newFlag = 1;
            ENGINE.setGlobalKV(_initializeKey(attackerPlayerIndex, activeMonIndex), bytes32(newFlag));
        }
        // Otherwise we don't do anything
    }

    function _applyBuff(uint256 playerIndex, uint256 monIndex) internal {
        STAT_BOOSTS.addStatBoost(
            playerIndex,
            monIndex,
            uint256(MonStateIndexName.SpecialAttack),
            SP_ATTACK_BUFF_PERCENT,
            StatBoostType.Multiply,
            StatBoostFlag.Temp
        );
        STAT_BOOSTS.addStatBoost(
            playerIndex,
            monIndex,
            uint256(MonStateIndexName.Attack),
            ATTACK_BUFF_PERCENT,
            StatBoostType.Multiply,
            StatBoostFlag.Temp
        );
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 1;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Mythic;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Self;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    /**
     Effect implementation
     */
    function _encodeState(uint256 playerIndex, uint256 monIndex) internal pure returns (bytes memory) {
        return abi.encode(playerIndex, monIndex);
    }

    function _decodeState(bytes memory data) internal pure returns (uint256 playerIndex, uint256 monIndex) {
        return abi.decode(data, (uint256, uint256));
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.OnMonSwitchIn || step == EffectStep.OnMonSwitchOut);
    }

    function onMonSwitchOut(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun) {
        // Clear the initialize lock, but do not remove effect
        (uint256 attackerPlayerIndex, uint256 attackingMonIndex) = _decodeState(extraData);
        if ((attackerPlayerIndex == targetIndex) && (attackingMonIndex == monIndex)) {
            ENGINE.setGlobalKV(_initializeKey(attackerPlayerIndex, attackingMonIndex), 0);
        }
        return (extraData, false);
    }
    
    function onMonSwitchIn(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun) {
        (uint256 attackerPlayerIndex,) = _decodeState(extraData);
        if (attackerPlayerIndex == targetIndex) {
            // Give the buff to the next mon
            _applyBuff(attackerPlayerIndex, monIndex);

            // We remove the effect from global tracking
            return (extraData, true);
        }
        return (extraData, false);
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}
