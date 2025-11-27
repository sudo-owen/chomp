// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName, StatBoostFlag, StatBoostType} from "../Enums.sol";
import {EffectInstance, MonStats, StatBoostToApply, StatBoostUpdate} from "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";
import {IEffect} from "./IEffect.sol";

/**
 * Usage Notes:
 *  - Each effect instance stores ONE boost source in bytes32 format
 *  - Multiple boosts = multiple effect instances
 *  - Snapshot (aggregated multipliers) stored in globalKV
 *
 *  Extra Data Layout (bytes32):
 *  [1 bit isPerm | 175 bits key | 80 bits stat data]
 *  stat data = 5 stats × 16 bits: [8 boostPercent | 7 boostCount | 1 isMultiply]
 *
 *  Snapshot stored in globalKV with key: keccak256(targetIndex, monIndex, "StatBoostSnapshot")
 *  Snapshot layout: [32 empty | 32 atk | 32 def | 32 spatk | 32 spdef | 32 speed | 64 empty]
 */

contract StatBoosts is BasicEffect {
    uint256 public constant DENOM = 100;
    // Layout: [8 bits isPerm | 168 bits key | 80 bits stat data]
    uint256 private constant PERM_FLAG_OFFSET = 248; // 256 - 8 = 248
    uint256 private constant KEY_OFFSET = 80;
    uint256 private constant KEY_MASK = (1 << 168) - 1;

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override returns (string memory) {
        return "Stat Boost";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return (r == EffectStep.OnMonSwitchOut);
    }

    // Removes all temporary boosts on mon switch out
    function onMonSwitchOut(uint256, bytes32 extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes32, bool)
    {
        // Check if this is a temp boost (isPerm flag is 0)
        bool isPerm = _isPerm(extraData);
        if (!isPerm) {
            // This is a temp boost, remove it and recalculate stats
            // Pass excludeTempBoosts=true since all temp boosts are being removed
            _recalculateAndApplyStats(targetIndex, monIndex, true);
            return (extraData, true); // Remove this effect
        }
        return (extraData, false);
    }

    function _isPerm(bytes32 data) internal pure returns (bool) {
        return uint8(uint256(data) >> PERM_FLAG_OFFSET) != 0;
    }

    function _snapshotKey(uint256 targetIndex, uint256 monIndex) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, address(this)));
    }

    // Pack boost instance with isPerm flag
    // Layout: [8 bits isPerm | 168 bits key | 80 bits stat data]
    function _packBoostData(uint168 key, bool isPerm, StatBoostToApply[] memory statBoostsToApply)
        internal
        pure
        returns (bytes32)
    {
        uint256 packed = isPerm ? (uint256(1) << PERM_FLAG_OFFSET) : 0;
        packed |= uint256(key) << KEY_OFFSET;

        for (uint256 i = 0; i < statBoostsToApply.length; i++) {
            uint256 statIndex = _monStateIndexToStatBoostIndex(statBoostsToApply[i].stat);
            uint256 offset = statIndex * 16;
            bool isMultiply = statBoostsToApply[i].boostType == StatBoostType.Multiply;
            uint256 boostInstance = (uint256(statBoostsToApply[i].boostPercent) << 8) | (1 << 1) | (isMultiply ? 1 : 0);
            packed |= boostInstance << offset;
        }
        return bytes32(packed);
    }

    function _unpackBoostData(bytes32 data)
        internal
        pure
        returns (bool isPerm, uint168 key, uint8[] memory boostPercents, uint8[] memory boostCounts, bool[] memory isMultiply)
    {
        uint256 packed = uint256(data);
        isPerm = uint8(packed >> PERM_FLAG_OFFSET) != 0;
        key = uint168((packed >> KEY_OFFSET) & KEY_MASK);
        boostPercents = new uint8[](5);
        boostCounts = new uint8[](5);
        isMultiply = new bool[](5);
        for (uint256 i = 0; i < 5; i++) {
            uint256 offset = i * 16;
            uint256 boostInstance = (packed >> offset) & 0xFFFF;
            boostPercents[i] = uint8(boostInstance >> 8);
            boostCounts[i] = uint8((boostInstance >> 1) & 0x7F);
            isMultiply[i] = (boostInstance & 0x1) == 1;
        }
    }

    function _generateKey(uint256 targetIndex, uint256 monIndex, address caller, string memory salt)
        internal
        pure
        returns (uint168)
    {
        return uint168(uint256(keccak256(abi.encode(targetIndex, monIndex, caller, salt))));
    }

    // Find existing boost with matching key
    function _findExistingBoostWithKey(uint256 targetIndex, uint256 monIndex, uint168 key, bool isPerm)
        internal
        view
        returns (bool found, uint256 effectIndex, bytes32 extraData)
    {
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(ENGINE.battleKeyForWrite(), targetIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                (bool existingIsPerm, uint168 existingKey,,,) = _unpackBoostData(effects[i].data);
                if (existingKey == key && existingIsPerm == isPerm) {
                    return (true, indices[i], effects[i].data);
                }
            }
        }
        return (false, 0, bytes32(0));
    }

    function _packBoostSnapshot(uint32[] memory unpackedSnapshot) internal pure returns (uint256) {
        return (uint256(unpackedSnapshot[0]) << 192) | (uint256(unpackedSnapshot[1]) << 160)
            | (uint256(unpackedSnapshot[2]) << 128) | (uint256(unpackedSnapshot[3]) << 96)
            | (uint256(unpackedSnapshot[4]) << 64);
    }

    function _unpackBoostSnapshot(uint256 playerIndex, uint256 monIndex, uint256 boostSnapshot)
        internal
        view
        returns (uint32[] memory snapshotPerStat)
    {
        snapshotPerStat = new uint32[](5);
        snapshotPerStat[0] = uint32((boostSnapshot >> 192) & 0xFFFFFFFF);
        snapshotPerStat[1] = uint32((boostSnapshot >> 160) & 0xFFFFFFFF);
        snapshotPerStat[2] = uint32((boostSnapshot >> 128) & 0xFFFFFFFF);
        snapshotPerStat[3] = uint32((boostSnapshot >> 96) & 0xFFFFFFFF);
        snapshotPerStat[4] = uint32((boostSnapshot >> 64) & 0xFFFFFFFF);
        uint32[] memory stats = _getMonStatSubset(playerIndex, monIndex);
        for (uint256 i; i < snapshotPerStat.length; i++) {
            if (snapshotPerStat[i] == 0) {
                snapshotPerStat[i] = stats[i];
            }
        }
        return snapshotPerStat;
    }

    function _monStateIndexToStatBoostIndex(MonStateIndexName statIndex) internal pure returns (uint256) {
        if (statIndex == MonStateIndexName.Attack) {
            return 0;
        } else if (statIndex == MonStateIndexName.Defense) {
            return 1;
        } else if (statIndex == MonStateIndexName.SpecialAttack) {
            return 2;
        } else if (statIndex == MonStateIndexName.SpecialDefense) {
            return 3;
        } else if (statIndex == MonStateIndexName.Speed) {
            return 4;
        }
        return 0;
    }

    function _statBoostIndexToMonStateIndex(uint256 statBoostIndex) internal pure returns (MonStateIndexName) {
        if (statBoostIndex == 0) {
            return MonStateIndexName.Attack;
        } else if (statBoostIndex == 1) {
            return MonStateIndexName.Defense;
        } else if (statBoostIndex == 2) {
            return MonStateIndexName.SpecialAttack;
        } else if (statBoostIndex == 3) {
            return MonStateIndexName.SpecialDefense;
        } else if (statBoostIndex == 4) {
            return MonStateIndexName.Speed;
        }
        return MonStateIndexName.Attack;
    }

    function _getMonStatSubset(uint256 playerIndex, uint256 monIndex) internal view returns (uint32[] memory) {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint32[] memory stats = new uint32[](5);
        MonStats memory monStats = ENGINE.getMonStatsForBattle(battleKey, playerIndex, monIndex);
        stats[0] = monStats.attack;
        stats[1] = monStats.defense;
        stats[2] = monStats.specialAttack;
        stats[3] = monStats.specialDefense;
        stats[4] = monStats.speed;
        return stats;
    }

    // Recalculate stats by iterating through all StatBoosts effects
    // If excludeTempBoosts is true, skip temp boosts (used during onMonSwitchOut when temp boosts are being removed)
    function _recalculateAndApplyStats(uint256 targetIndex, uint256 monIndex, bool excludeTempBoosts) internal {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 prevSnapshot = uint256(ENGINE.getGlobalKV(battleKey, _snapshotKey(targetIndex, monIndex)));

        (EffectInstance[] memory effects,) = ENGINE.getEffects(battleKey, targetIndex, monIndex);

        uint32[] memory oldBoostedStats = _unpackBoostSnapshot(targetIndex, monIndex, prevSnapshot);
        uint32[] memory stats = _getMonStatSubset(targetIndex, monIndex);
        uint32[] memory newBoostedStats = new uint32[](5);
        uint32[] memory numBoostsPerStat = new uint32[](5);
        uint256[] memory accumulatedNumeratorPerStat = new uint256[](5);

        // Iterate through all StatBoosts effects and aggregate
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                (bool isPerm, , uint8[] memory boostPercents, uint8[] memory boostCounts, bool[] memory isMultiply) =
                    _unpackBoostData(effects[i].data);
                // Skip temp boosts if excludeTempBoosts is true
                if (excludeTempBoosts && !isPerm) continue;
                for (uint256 k = 0; k < 5; k++) {
                    if (boostCounts[k] == 0) continue;
                    uint256 existingStatValue = (accumulatedNumeratorPerStat[k] == 0) ? stats[k] : accumulatedNumeratorPerStat[k];
                    uint256 scalingFactor = isMultiply[k] ? DENOM + boostPercents[k] : DENOM - boostPercents[k];
                    accumulatedNumeratorPerStat[k] = existingStatValue * (scalingFactor ** boostCounts[k]);
                    numBoostsPerStat[k] += boostCounts[k];
                }
            }
        }

        // Calculate final values
        for (uint256 i = 0; i < 5; i++) {
            if (numBoostsPerStat[i] > 0) {
                newBoostedStats[i] = uint32(accumulatedNumeratorPerStat[i] / (DENOM ** numBoostsPerStat[i]));
            } else {
                newBoostedStats[i] = stats[i];
            }
        }

        // Apply deltas
        for (uint256 i = 0; i < 5; i++) {
            int32 delta = int32(newBoostedStats[i]) - int32(oldBoostedStats[i]);
            if (delta != 0) {
                ENGINE.updateMonState(targetIndex, monIndex, _statBoostIndexToMonStateIndex(i), delta);
            }
        }

        // Update snapshot in globalKV
        ENGINE.setGlobalKV(_snapshotKey(targetIndex, monIndex), bytes32(_packBoostSnapshot(newBoostedStats)));
    }

    function _mergeExistingAndNewBoosts(
        uint8[] memory existingBoostPercents,
        uint8[] memory existingBoostCounts,
        bool[] memory existingIsMultiply,
        StatBoostToApply[] memory newBoostsToApply
    )
        internal
        pure
        returns (uint8[] memory mergedBoostPercents, uint8[] memory mergedBoostCounts, bool[] memory mergedIsMultiply)
    {
        mergedBoostPercents = existingBoostPercents;
        mergedBoostCounts = existingBoostCounts;
        mergedIsMultiply = existingIsMultiply;
        for (uint256 i; i < newBoostsToApply.length; i++) {
            uint256 statIndex = _monStateIndexToStatBoostIndex(newBoostsToApply[i].stat);
            if (existingBoostPercents[statIndex] != 0) {
                mergedBoostCounts[statIndex]++;
            } else {
                mergedBoostPercents[statIndex] = newBoostsToApply[i].boostPercent;
                mergedBoostCounts[statIndex] = 1;
                mergedIsMultiply[statIndex] = newBoostsToApply[i].boostType == StatBoostType.Multiply;
            }
        }
        return (mergedBoostPercents, mergedBoostCounts, mergedIsMultiply);
    }

    function _packBoostDataWithArrays(uint168 key, bool isPerm, uint8[] memory boostPercents, uint8[] memory boostCounts, bool[] memory isMultiply)
        internal
        pure
        returns (bytes32)
    {
        uint256 packed = isPerm ? (uint256(1) << PERM_FLAG_OFFSET) : 0;
        packed |= uint256(key) << KEY_OFFSET;

        for (uint256 i = 0; i < 5; i++) {
            uint256 offset = i * 16;
            uint256 boostInstance = (uint256(boostPercents[i]) << 8) | (uint256(boostCounts[i]) << 1) | (isMultiply[i] ? 1 : 0);
            packed |= boostInstance << offset;
        }
        return bytes32(packed);
    }

    function addStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag
    ) public {
        uint168 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function addKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        string memory keyToUse
    ) public {
        uint168 key = _generateKey(targetIndex, monIndex, msg.sender, keyToUse);
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function _addStatBoostsWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        uint168 key
    ) internal {
        bool isPerm = boostFlag == StatBoostFlag.Perm;

        // Check if effect with this key already exists
        (bool found, uint256 effectIndex, bytes32 existingData) = _findExistingBoostWithKey(targetIndex, monIndex, key, isPerm);

        bytes32 newData;
        if (found) {
            // Merge with existing boost
            (, , uint8[] memory existingBoostPercents, uint8[] memory existingBoostCounts, bool[] memory existingIsMultiply) =
                _unpackBoostData(existingData);
            (uint8[] memory mergedPercents, uint8[] memory mergedCounts, bool[] memory mergedIsMultiply) =
                _mergeExistingAndNewBoosts(existingBoostPercents, existingBoostCounts, existingIsMultiply, statBoostsToApply);
            newData = _packBoostDataWithArrays(key, isPerm, mergedPercents, mergedCounts, mergedIsMultiply);
            ENGINE.editEffect(targetIndex, monIndex, effectIndex, newData);
        } else {
            // Create new effect
            newData = _packBoostData(key, isPerm, statBoostsToApply);
            ENGINE.addEffect(targetIndex, monIndex, IEffect(address(this)), newData);
        }

        // Recalculate and apply stats
        _recalculateAndApplyStats(targetIndex, monIndex, false);
    }

    function removeStatBoosts(uint256 targetIndex, uint256 monIndex, StatBoostFlag boostFlag) public {
        uint168 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function removeKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostFlag boostFlag,
        string memory stringToUse
    ) public {
        uint168 key = _generateKey(targetIndex, monIndex, msg.sender, stringToUse);
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function _removeStatBoostsWithKey(uint256 targetIndex, uint256 monIndex, uint168 key, StatBoostFlag boostFlag) internal {
        bool isPerm = boostFlag == StatBoostFlag.Perm;
        (bool found, uint256 effectIndex,) = _findExistingBoostWithKey(targetIndex, monIndex, key, isPerm);

        if (found) {
            // Remove the effect by setting data to 0 (effect will be cleaned up)
            ENGINE.removeEffect(targetIndex, monIndex, effectIndex);
            // Recalculate stats
            _recalculateAndApplyStats(targetIndex, monIndex, false);
        }
    }
}
