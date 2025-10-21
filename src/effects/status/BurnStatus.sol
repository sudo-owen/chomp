// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";

import {StatBoosts} from "../StatBoosts.sol";
import {StatusEffect} from "./StatusEffect.sol";
import {StatusEffectLib} from "./StatusEffectLib.sol";

contract BurnStatus is StatusEffect {
    uint256 public constant MAX_BURN_DEGREE = 3;

    int32 public constant ATTACK_PERCENT = 50;

    int32 public constant DEG1_DAMAGE_DENOM = 16;
    int32 public constant DEG2_DAMAGE_DENOM = 8;
    int32 public constant DEG3_DAMAGE_DENOM = 4;

    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine engine, StatBoosts statBoosts) StatusEffect(engine) {
        STAT_BOOSTS = statBoosts;
    }

    function name() public pure override returns (string memory) {
        return "Burn";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        // Need to also return OnRemove to remove the global status flag
        return
            (r == EffectStep.RoundStart || r == EffectStep.RoundEnd || r == EffectStep.OnApply
                    || r == EffectStep.OnRemove);
    }

    function shouldApply(bytes memory, uint256 targetIndex, uint256 monIndex) public override returns (bool) {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        bytes32 keyForMon = StatusEffectLib.getKeyForMonIndex(targetIndex, monIndex);

        // Get value from ENGINE KV
        bytes32 monStatusFlag = ENGINE.getGlobalKV(battleKey, keyForMon);

        // Check if a status already exists for the mon
        if (monStatusFlag == bytes32(0)) {
            // If not, set the value to be the address of the status and return true
            ENGINE.setGlobalKV(keyForMon, bytes32(uint256(uint160(address(this)))));
            return true;
        } else {
            // Otherwise check if it is burn
            if (monStatusFlag == bytes32(uint256(uint160(address(this))))) {
                // If it is burn, add an additional stack
                _increaseBurnDegree(targetIndex, monIndex);
            }
        }
        return false;
    }

    function getKeyForMonIndex(uint256 targetIndex, uint256 monIndex) public pure returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, name()));
    }

    function _getBurnDegree(uint256 playerIndex, uint256 monIndex) internal view returns (uint256) {
        return uint256(ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), getKeyForMonIndex(playerIndex, monIndex)));
    }

    function _increaseBurnDegree(uint256 playerIndex, uint256 monIndex) internal {
        uint256 currentBurnDegree = _getBurnDegree(playerIndex, monIndex);
        uint256 newBurnDegree = currentBurnDegree + 1;
        if (newBurnDegree <= MAX_BURN_DEGREE) {
            ENGINE.setGlobalKV(getKeyForMonIndex(playerIndex, monIndex), bytes32(newBurnDegree));
        }
    }

    function onApply(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        _increaseBurnDegree(targetIndex, monIndex);

        // Reduce attack by 1/ATTACK_DENOM of base attack stat
        STAT_BOOSTS.addStatBoost(
            targetIndex,
            monIndex,
            uint256(MonStateIndexName.Attack),
            ATTACK_PERCENT,
            StatBoostType.Divide,
            StatBoostFlag.Perm
        );

        return ("", false);
    }

    function onRemove(bytes memory, uint256 targetIndex, uint256 monIndex) public override {
        // Remove the base status flag
        super.onRemove("", targetIndex, monIndex);

        // Reset the attack reduction
        STAT_BOOSTS.removeStatBoost(
            targetIndex,
            monIndex,
            uint256(MonStateIndexName.Attack),
            ATTACK_PERCENT,
            StatBoostType.Divide,
            StatBoostFlag.Perm
        );

        // Reset the burn degree
        ENGINE.setGlobalKV(getKeyForMonIndex(targetIndex, monIndex), bytes32(0));
    }

    // Deal damage over time
    function onRoundEnd(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        uint256 burnDegree = _getBurnDegree(targetIndex, monIndex);
        int32 damageDenom = DEG1_DAMAGE_DENOM;
        if (burnDegree == 2) {
            damageDenom = DEG2_DAMAGE_DENOM;
        }
        if (burnDegree == 3) {
            damageDenom = DEG3_DAMAGE_DENOM;
        }
        int32 damage =
            int32(ENGINE.getMonValueForBattle(ENGINE.battleKeyForWrite(), targetIndex, monIndex, MonStateIndexName.Hp))
            / damageDenom;
        ENGINE.dealDamage(targetIndex, monIndex, damage);
        return ("", false);
    }
}
