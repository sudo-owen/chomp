// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";
import "../../Structs.sol";

import {IEngine} from "../../IEngine.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract ChainExpansion is IMoveSet, BasicEffect {

    uint256 constant public DURATION = 5;
    int32 constant public HEAL_DENOM = 8;
    int32 constant public DAMAGE_1_DENOM = 16;
    int32 constant public DAMAGE_2_DENOM = 8;
    int32 constant public DAMAGE_3_DENOM = 4;

    IEngine immutable ENGINE;
    ITypeCalculator immutable TYPE_CALC;

    constructor(IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR) {
        ENGINE = _ENGINE;
        TYPE_CALC = _TYPE_CALCULATOR;
    }

    function name() public pure override(IMoveSet, BasicEffect) returns (string memory) {
        return "Chain Expansion";
    }

    function _key(uint256 playerIndex, uint256 monIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, monIndex, name()));
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        // Check if the ability is already applied
        uint256 attackerMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
        bytes32 flag = ENGINE.getGlobalKV(battleKey, _key(attackerPlayerIndex, attackerMonIndex));
        if (flag == bytes32(0)) {

            // Apply this effect globaly
            ENGINE.addEffect(2, 2, this, _encodeState(DURATION, attackerPlayerIndex));

            // Set the new flag
            uint256 newFlag = 1;
            ENGINE.setGlobalKV(_key(attackerPlayerIndex, attackerMonIndex), bytes32(newFlag));
        }
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 4;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Mythic;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Other;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    /**
     Effect implementation
     */

    function _encodeState(uint256 turnsLeft, uint256 playerIndex) internal pure returns (bytes memory) {
        return abi.encode(turnsLeft, playerIndex);
    }

    function _decodeState(bytes memory data) internal pure returns (uint256 turnsLeft, uint256 playerIndex) {
        return abi.decode(data, (uint256, uint256));
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.OnMonSwitchIn || step == EffectStep.RoundEnd);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        external
        override
        returns (bytes memory, bool)
    {
        (uint256 turnsLeft, uint256 playerIndex) = _decodeState(extraData);
        if (turnsLeft == 1) {
            // Unset the global KV
            bytes32 battleKey = ENGINE.battleKeyForWrite();
            uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[playerIndex];
            ENGINE.setGlobalKV(_key(playerIndex, activeMonIndex), bytes32(0));
            return (extraData, true);
        } else {
            return (_encodeState(turnsLeft - 1, playerIndex), false);
        }
    }

    function onMonSwitchIn(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool) {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (, uint256 ownerIndex) = _decodeState(extraData);
        // If it's a friendly mon, then we heal (flat 1/8 of max HP)
        if (targetIndex == ownerIndex) {
            int32 amtToHeal = int32(ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Hp)) / HEAL_DENOM;
            int32 damageReceived = ENGINE.getMonStateForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Hp);
            // Prevent overhealing
            if (amtToHeal > (-1 * damageReceived)) {
                amtToHeal = -1 * damageReceived;
            }
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.Hp, amtToHeal);
        }
        // Otherwise, we deal damage (depending on type effectiveness)
        else {
            Type defenderT1 = Type(ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Type1));
            Type defenderT2 = Type(ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Type2));
            uint256 m1 = TYPE_CALC.getTypeEffectiveness(moveType(battleKey), defenderT1, 2);
            uint256 m2 = 2;
            if (defenderT2 != Type.None) {
                m2 = TYPE_CALC.getTypeEffectiveness(moveType(battleKey), defenderT2, 2);
            }
            uint256 scale = m1*m2;
            // Default value should be 4 
            // If > 4, then we shift up a damage tier
            // If < 4, then we shift down a damage tier
            int32 damageDenom = DAMAGE_2_DENOM;
            if (scale < 4) {
                damageDenom = DAMAGE_1_DENOM;
            }
            else if (scale > 4) {
                damageDenom = DAMAGE_3_DENOM;
            }
            int32 damageToDeal = int32(ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Hp)) / damageDenom;
            ENGINE.dealDamage(targetIndex, monIndex, damageToDeal);
        }
        return (extraData, false);
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}
