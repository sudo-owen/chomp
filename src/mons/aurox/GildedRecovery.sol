// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {StatusEffectLib} from "../../effects/status/StatusEffectLib.sol";

contract GildedRecovery is IMoveSet {
    int32 public constant HEAL_PERCENT = 50; 
    int32 public constant STAMINA_BONUS = 1;

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override returns (string memory) {
        return "Gilded Recovery";
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata extraData, uint256) external {
        // Decode the mon index from extraData
        (uint256 targetMonIndex) = abi.decode(extraData, (uint256));

        // Check if the target mon has a status effect
        bytes32 statusKey = StatusEffectLib.getKeyForMonIndex(attackerPlayerIndex, targetMonIndex);
        bytes32 statusFlag = ENGINE.getGlobalKV(battleKey, statusKey);

        // If the mon has a status effect, remove it and heal
        if (statusFlag != bytes32(0)) {
            // Find and remove the status effect
            (IEffect[] memory effects,) = ENGINE.getEffects(battleKey, attackerPlayerIndex, targetMonIndex);
            address statusEffectAddress = address(uint160(uint256(statusFlag)));

            for (uint256 i = 0; i < effects.length; i++) {
                if (address(effects[i]) == statusEffectAddress) {
                    ENGINE.removeEffect(attackerPlayerIndex, targetMonIndex, i);
                    break;
                }
            }
            // Give +1 stamina
            ENGINE.updateMonState(attackerPlayerIndex, targetMonIndex, MonStateIndexName.Stamina, STAMINA_BONUS);

            // Heal 50% of max HP for self
            uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
            int32 maxHp =
                int32(ENGINE.getMonValueForBattle(battleKey, attackerPlayerIndex, activeMonIndex, MonStateIndexName.Hp));
            int32 healAmount = (maxHp * HEAL_PERCENT) / 100;

            // Don't overheal
            int32 currentHpDelta =
                ENGINE.getMonStateForBattle(battleKey, attackerPlayerIndex, activeMonIndex, MonStateIndexName.Hp);
            if (currentHpDelta + healAmount > 0) {
                healAmount = -currentHpDelta;
            }

            if (healAmount != 0) {
                ENGINE.updateMonState(attackerPlayerIndex, activeMonIndex, MonStateIndexName.Hp, healAmount);
            }
        }
        // If no status effect, do nothing
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 2;
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

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.SelfTeamIndex;
    }
}