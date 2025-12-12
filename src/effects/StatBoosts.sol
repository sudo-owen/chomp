// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName, StatBoostFlag, StatBoostType} from "../Enums.sol";
import {EffectInstance, MonStats, StatBoostToApply, StatBoostUpdate} from "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";
import {IEffect} from "./IEffect.sol";

/**
 * Consolidated StatBoosts using KV storage
 *
 * Key design:
 *  - Only ONE effect instance per (targetIndex, monIndex)
 *  - All boost sources stored in KV slots
 *  - O(1) lookup by source key via KV index mapping
 *
 * Extra Data Layout (bytes32):
 *  [8 bits totalCount | 8 bits tempCount | 240 bits reserved]
 *
 * KV Storage:
 *  - Key-to-Index: keccak256(targetIndex, monIndex, address(this), "k2i", truncatedKey) => slotIndex (1-indexed)
 *  - Slot Data: keccak256(targetIndex, monIndex, address(this), "slot", slotIndex) => packed slot data
 *  - Snapshot: keccak256(targetIndex, monIndex, address(this)) => aggregated stats
 *
 * Slot Data Layout (192 bits):
 *  [bits 0-79: statData | bit 80: isPerm | bits 81-127: unused | bits 128-191: truncatedKey]
 *  Each stat (16 bits): [8 boostPercent | 7 boostCount | 1 isMultiply]
 */
contract StatBoosts is BasicEffect {
    uint256 public constant DENOM = 100;

    // ExtraData layout
    uint256 private constant TOTAL_COUNT_OFFSET = 248;
    uint256 private constant TEMP_COUNT_OFFSET = 240;
    uint256 private constant COUNT_MASK = 0xFF;

    // Slot data layout (within uint192)
    // bits 0-79: statData (80 bits = 5 stats × 16 bits)
    // bit 80: isPerm (1 bit)
    // bits 81-127: unused (47 bits)
    // bits 128-191: truncatedKey (64 bits)
    uint256 private constant SLOT_KEY_OFFSET = 128;
    uint256 private constant SLOT_PERM_BIT = 80;

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

    // ============ ExtraData Packing ============

    function _packExtraData(uint8 totalCount, uint8 tempCount) internal pure returns (bytes32) {
        return bytes32((uint256(totalCount) << TOTAL_COUNT_OFFSET) | (uint256(tempCount) << TEMP_COUNT_OFFSET));
    }

    function _unpackExtraData(bytes32 data) internal pure returns (uint8 totalCount, uint8 tempCount) {
        totalCount = uint8((uint256(data) >> TOTAL_COUNT_OFFSET) & COUNT_MASK);
        tempCount = uint8((uint256(data) >> TEMP_COUNT_OFFSET) & COUNT_MASK);
    }

    // ============ KV Key Generation ============

    function _kvKeyToIndex(uint256 targetIndex, uint256 monIndex, uint64 truncatedKey) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, address(this), "k2i", truncatedKey));
    }

    function _kvSlot(uint256 targetIndex, uint256 monIndex, uint8 slotIndex) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, address(this), "slot", slotIndex));
    }

    function _snapshotKey(uint256 targetIndex, uint256 monIndex) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, address(this)));
    }

    // ============ Slot Data Packing ============

    function _packSlotData(
        uint64 truncatedKey,
        bool isPerm,
        uint8[5] memory boostPercents,
        uint8[5] memory boostCounts,
        bool[5] memory isMultiply
    ) internal pure returns (uint192) {
        uint256 packed = uint256(truncatedKey) << SLOT_KEY_OFFSET;
        packed |= (isPerm ? uint256(1) : 0) << SLOT_PERM_BIT;

        for (uint256 i = 0; i < 5; i++) {
            uint256 offset = i * 16;
            uint256 statData = (uint256(boostPercents[i]) << 8) | (uint256(boostCounts[i]) << 1) | (isMultiply[i] ? 1 : 0);
            packed |= statData << offset;
        }
        return uint192(packed);
    }

    function _unpackSlotData(uint192 data)
        internal
        pure
        returns (
            uint64 truncatedKey,
            bool isPerm,
            uint8[5] memory boostPercents,
            uint8[5] memory boostCounts,
            bool[5] memory isMultiply
        )
    {
        truncatedKey = uint64(uint256(data) >> SLOT_KEY_OFFSET);
        isPerm = ((uint256(data) >> SLOT_PERM_BIT) & 0x1) != 0;

        for (uint256 i = 0; i < 5; i++) {
            uint256 offset = i * 16;
            uint256 statData = (uint256(data) >> offset) & 0xFFFF;
            boostPercents[i] = uint8(statData >> 8);
            boostCounts[i] = uint8((statData >> 1) & 0x7F);
            isMultiply[i] = (statData & 0x1) == 1;
        }
    }

    function _packSlotDataFromApply(uint64 truncatedKey, bool isPerm, StatBoostToApply[] memory boosts)
        internal
        pure
        returns (uint192)
    {
        uint8[5] memory boostPercents;
        uint8[5] memory boostCounts;
        bool[5] memory isMultiply;

        for (uint256 i = 0; i < boosts.length; i++) {
            uint256 statIndex = _monStateIndexToStatBoostIndex(boosts[i].stat);
            boostPercents[statIndex] = boosts[i].boostPercent;
            boostCounts[statIndex] = 1;
            isMultiply[statIndex] = boosts[i].boostType == StatBoostType.Multiply;
        }

        return _packSlotData(truncatedKey, isPerm, boostPercents, boostCounts, isMultiply);
    }

    // ============ Stat Index Mapping ============

    function _monStateIndexToStatBoostIndex(MonStateIndexName statIndex) internal pure returns (uint256) {
        uint256 idx = uint256(statIndex);
        if (idx == 2) return 4; // Speed
        return idx - 3; // Attack(3)->0, Defense(4)->1, SpAtk(5)->2, SpDef(6)->3
    }

    function _statBoostIndexToMonStateIndex(uint256 statBoostIndex) internal pure returns (MonStateIndexName) {
        if (statBoostIndex == 4) return MonStateIndexName.Speed;
        return MonStateIndexName(statBoostIndex + 3);
    }

    // ============ Snapshot Packing ============

    function _packBoostSnapshot(uint32[5] memory stats) internal pure returns (uint192) {
        return uint192(
            (uint256(stats[0]) << 160) | (uint256(stats[1]) << 128) | (uint256(stats[2]) << 96)
                | (uint256(stats[3]) << 64) | (uint256(stats[4]) << 32)
        );
    }

    function _unpackBoostSnapshot(uint192 boostSnapshot, uint32[5] memory baseStats)
        internal
        pure
        returns (uint32[5] memory snapshotPerStat)
    {
        snapshotPerStat[0] = uint32((boostSnapshot >> 160) & 0xFFFFFFFF);
        snapshotPerStat[1] = uint32((boostSnapshot >> 128) & 0xFFFFFFFF);
        snapshotPerStat[2] = uint32((boostSnapshot >> 96) & 0xFFFFFFFF);
        snapshotPerStat[3] = uint32((boostSnapshot >> 64) & 0xFFFFFFFF);
        snapshotPerStat[4] = uint32((boostSnapshot >> 32) & 0xFFFFFFFF);
        for (uint256 i; i < 5; i++) {
            if (snapshotPerStat[i] == 0) {
                snapshotPerStat[i] = baseStats[i];
            }
        }
    }

    // ============ Helper Functions ============

    function _generateKey(uint256 targetIndex, uint256 monIndex, address caller, string memory salt)
        internal
        pure
        returns (uint64)
    {
        // Truncate to 64 bits for KV storage efficiency
        return uint64(uint256(keccak256(abi.encode(targetIndex, monIndex, caller, salt))));
    }

    function _getMonStatSubset(bytes32 battleKey, uint256 playerIndex, uint256 monIndex)
        internal
        view
        returns (uint32[5] memory stats)
    {
        MonStats memory monStats = ENGINE.getMonStatsForBattle(battleKey, playerIndex, monIndex);
        stats[0] = monStats.attack;
        stats[1] = monStats.defense;
        stats[2] = monStats.specialAttack;
        stats[3] = monStats.specialDefense;
        stats[4] = monStats.speed;
    }

    function _denomPower(uint256 exp) internal pure returns (uint256) {
        if (exp == 0) return 1;
        if (exp == 1) return 100;
        if (exp == 2) return 10000;
        if (exp == 3) return 1000000;
        if (exp == 4) return 100000000;
        if (exp == 5) return 10000000000;
        if (exp == 6) return 1000000000000;
        if (exp == 7) return 100000000000000;
        return DENOM ** exp;
    }

    function _accumulateBoosts(
        uint32[5] memory baseStats,
        uint8[5] memory boostPercents,
        uint8[5] memory boostCounts,
        bool[5] memory isMultiply,
        uint32[5] memory numBoostsPerStat,
        uint256[5] memory accumulatedNumeratorPerStat
    ) internal pure {
        for (uint256 k = 0; k < 5; k++) {
            if (boostCounts[k] == 0) continue;
            uint256 existingStatValue =
                (accumulatedNumeratorPerStat[k] == 0) ? baseStats[k] : accumulatedNumeratorPerStat[k];
            uint256 scalingFactor = isMultiply[k] ? DENOM + boostPercents[k] : DENOM - boostPercents[k];
            accumulatedNumeratorPerStat[k] = existingStatValue * (scalingFactor ** boostCounts[k]);
            numBoostsPerStat[k] += boostCounts[k];
        }
    }

    // ============ Core Logic ============

    function _findEffectIndex(bytes32 battleKey, uint256 targetIndex, uint256 monIndex)
        internal
        view
        returns (bool found, uint256 effectIndex, bytes32 extraData)
    {
        (EffectInstance[] memory effects, uint256[] memory indices) =
            ENGINE.getEffects(battleKey, targetIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                return (true, indices[i], effects[i].data);
            }
        }
        return (false, 0, bytes32(0));
    }

    function _recalculateAndApplyStats(
        bytes32 battleKey,
        uint256 targetIndex,
        uint256 monIndex,
        uint8 totalCount,
        bool excludeTempBoosts
    ) internal {
        uint32[5] memory baseStats = _getMonStatSubset(battleKey, targetIndex, monIndex);
        bytes32 snapshotKVKey = _snapshotKey(targetIndex, monIndex);
        uint192 prevSnapshot = ENGINE.getGlobalKV(battleKey, snapshotKVKey);
        uint32[5] memory oldBoostedStats = _unpackBoostSnapshot(prevSnapshot, baseStats);

        uint32[5] memory numBoostsPerStat;
        uint256[5] memory accumulatedNumeratorPerStat;

        // Iterate through all slots
        for (uint8 i = 1; i <= totalCount; i++) {
            bytes32 slotKey = _kvSlot(targetIndex, monIndex, i);
            uint192 slotData = ENGINE.getGlobalKV(battleKey, slotKey);
            if (slotData == 0) continue;

            (
                ,
                bool isPerm,
                uint8[5] memory boostPercents,
                uint8[5] memory boostCounts,
                bool[5] memory isMultiply
            ) = _unpackSlotData(slotData);

            if (excludeTempBoosts && !isPerm) continue;

            _accumulateBoosts(
                baseStats, boostPercents, boostCounts, isMultiply, numBoostsPerStat, accumulatedNumeratorPerStat
            );
        }

        // Calculate final values
        uint32[5] memory newBoostedStats;
        for (uint256 i = 0; i < 5; i++) {
            if (numBoostsPerStat[i] > 0) {
                newBoostedStats[i] = uint32(accumulatedNumeratorPerStat[i] / _denomPower(numBoostsPerStat[i]));
            } else {
                newBoostedStats[i] = baseStats[i];
            }
        }

        // Apply deltas
        for (uint256 i = 0; i < 5; i++) {
            int32 delta = int32(newBoostedStats[i]) - int32(oldBoostedStats[i]);
            if (delta != 0) {
                ENGINE.updateMonState(targetIndex, monIndex, _statBoostIndexToMonStateIndex(i), delta);
            }
        }

        // Update snapshot
        ENGINE.setGlobalKV(snapshotKVKey, _packBoostSnapshot(newBoostedStats));
    }

    // ============ Public Interface ============

    function addStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag
    ) public {
        uint64 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function addKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        string memory keyToUse
    ) public {
        uint64 key = _generateKey(targetIndex, monIndex, msg.sender, keyToUse);
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function _addStatBoostsWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        uint64 key
    ) internal {
        bool isPerm = boostFlag == StatBoostFlag.Perm;
        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Find or create the single StatBoosts effect
        (bool effectFound, uint256 effectIndex, bytes32 extraData) =
            _findEffectIndex(battleKey, targetIndex, monIndex);

        uint8 totalCount;
        uint8 tempCount;
        if (effectFound) {
            (totalCount, tempCount) = _unpackExtraData(extraData);
        }

        // Check if this key already has a slot
        bytes32 k2iKey = _kvKeyToIndex(targetIndex, monIndex, key);
        uint192 existingSlotIndex = ENGINE.getGlobalKV(battleKey, k2iKey);

        if (existingSlotIndex != 0) {
            // Update existing slot - merge boosts
            uint8 slotIdx = uint8(existingSlotIndex);
            bytes32 slotKey = _kvSlot(targetIndex, monIndex, slotIdx);
            uint192 existingSlotData = ENGINE.getGlobalKV(battleKey, slotKey);

            (
                ,
                bool existingIsPerm,
                uint8[5] memory existingPercents,
                uint8[5] memory existingCounts,
                bool[5] memory existingIsMultiply
            ) = _unpackSlotData(existingSlotData);

            // Merge new boosts into existing
            for (uint256 i = 0; i < statBoostsToApply.length; i++) {
                uint256 statIndex = _monStateIndexToStatBoostIndex(statBoostsToApply[i].stat);
                if (existingPercents[statIndex] != 0) {
                    existingCounts[statIndex]++;
                } else {
                    existingPercents[statIndex] = statBoostsToApply[i].boostPercent;
                    existingCounts[statIndex] = 1;
                    existingIsMultiply[statIndex] = statBoostsToApply[i].boostType == StatBoostType.Multiply;
                }
            }

            uint192 newSlotData =
                _packSlotData(key, existingIsPerm, existingPercents, existingCounts, existingIsMultiply);
            ENGINE.setGlobalKV(slotKey, newSlotData);
        } else {
            // Create new slot
            totalCount++;
            if (!isPerm) tempCount++;

            // Write key-to-index mapping
            ENGINE.setGlobalKV(k2iKey, uint192(totalCount));

            // Write slot data
            bytes32 slotKey = _kvSlot(targetIndex, monIndex, totalCount);
            uint192 slotData = _packSlotDataFromApply(key, isPerm, statBoostsToApply);
            ENGINE.setGlobalKV(slotKey, slotData);

            // Update effect extraData
            bytes32 newExtraData = _packExtraData(totalCount, tempCount);
            if (effectFound) {
                ENGINE.editEffect(targetIndex, monIndex, effectIndex, newExtraData);
            } else {
                ENGINE.addEffect(targetIndex, monIndex, IEffect(address(this)), newExtraData);
            }
        }

        // Recalculate and apply stats
        _recalculateAndApplyStats(battleKey, targetIndex, monIndex, totalCount, false);
    }

    function removeStatBoosts(uint256 targetIndex, uint256 monIndex, StatBoostFlag boostFlag) public {
        uint64 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function removeKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostFlag boostFlag,
        string memory stringToUse
    ) public {
        uint64 key = _generateKey(targetIndex, monIndex, msg.sender, stringToUse);
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function _removeStatBoostsWithKey(uint256 targetIndex, uint256 monIndex, uint64 key, StatBoostFlag boostFlag)
        internal
    {
        bool isPerm = boostFlag == StatBoostFlag.Perm;
        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Find the effect
        (bool effectFound, uint256 effectIndex, bytes32 extraData) =
            _findEffectIndex(battleKey, targetIndex, monIndex);
        if (!effectFound) return;

        (uint8 totalCount, uint8 tempCount) = _unpackExtraData(extraData);

        // Find the slot for this key
        bytes32 k2iKey = _kvKeyToIndex(targetIndex, monIndex, key);
        uint192 slotIndexRaw = ENGINE.getGlobalKV(battleKey, k2iKey);
        if (slotIndexRaw == 0) return;

        uint8 slotToRemove = uint8(slotIndexRaw);

        // Verify isPerm matches
        bytes32 slotKey = _kvSlot(targetIndex, monIndex, slotToRemove);
        uint192 slotData = ENGINE.getGlobalKV(battleKey, slotKey);
        (, bool slotIsPerm,,,) = _unpackSlotData(slotData);
        if (slotIsPerm != isPerm) return;

        // Swap with last slot if not already last
        if (slotToRemove != totalCount) {
            bytes32 lastSlotKey = _kvSlot(targetIndex, monIndex, totalCount);
            uint192 lastSlotData = ENGINE.getGlobalKV(battleKey, lastSlotKey);
            (uint64 lastKey,,,,) = _unpackSlotData(lastSlotData);

            // Move last slot data to the removed slot
            ENGINE.setGlobalKV(slotKey, lastSlotData);

            // Update key-to-index for the moved slot
            bytes32 lastK2iKey = _kvKeyToIndex(targetIndex, monIndex, lastKey);
            ENGINE.setGlobalKV(lastK2iKey, uint192(slotToRemove));

            // Clear the last slot
            ENGINE.setGlobalKV(lastSlotKey, 0);
        } else {
            // Just clear the slot
            ENGINE.setGlobalKV(slotKey, 0);
        }

        // Clear the key-to-index for removed key
        ENGINE.setGlobalKV(k2iKey, 0);

        // Update counts
        totalCount--;
        if (!isPerm) tempCount--;

        // Update or remove effect
        if (totalCount == 0) {
            ENGINE.removeEffect(targetIndex, monIndex, effectIndex);
        } else {
            ENGINE.editEffect(targetIndex, monIndex, effectIndex, _packExtraData(totalCount, tempCount));
        }

        // Recalculate and apply stats
        _recalculateAndApplyStats(battleKey, targetIndex, monIndex, totalCount, false);
    }

    // ============ Effect Hooks ============

    function onMonSwitchOut(uint256, bytes32 extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes32, bool)
    {
        (uint8 totalCount, uint8 tempCount) = _unpackExtraData(extraData);

        if (tempCount == 0) {
            // No temp boosts to remove
            return (extraData, false);
        }

        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Remove all temp boosts using swap-and-pop
        uint8 i = 1;
        while (i <= totalCount) {
            bytes32 slotKey = _kvSlot(targetIndex, monIndex, i);
            uint192 slotData = ENGINE.getGlobalKV(battleKey, slotKey);
            if (slotData == 0) {
                i++;
                continue;
            }

            (uint64 slotTruncatedKey, bool isPerm,,,) = _unpackSlotData(slotData);

            if (!isPerm) {
                // This is a temp boost, remove it
                // Clear key-to-index
                bytes32 k2iKey = _kvKeyToIndex(targetIndex, monIndex, slotTruncatedKey);
                ENGINE.setGlobalKV(k2iKey, 0);

                if (i != totalCount) {
                    // Swap with last
                    bytes32 lastSlotKey = _kvSlot(targetIndex, monIndex, totalCount);
                    uint192 lastSlotData = ENGINE.getGlobalKV(battleKey, lastSlotKey);
                    (uint64 lastKey,,,,) = _unpackSlotData(lastSlotData);

                    ENGINE.setGlobalKV(slotKey, lastSlotData);

                    bytes32 lastK2iKey = _kvKeyToIndex(targetIndex, monIndex, lastKey);
                    ENGINE.setGlobalKV(lastK2iKey, uint192(i));

                    ENGINE.setGlobalKV(lastSlotKey, 0);
                } else {
                    ENGINE.setGlobalKV(slotKey, 0);
                }

                totalCount--;
                tempCount--;
                // Don't increment i, check the swapped-in slot
            } else {
                i++;
            }
        }

        // Recalculate stats (all remaining boosts are perm)
        _recalculateAndApplyStats(battleKey, targetIndex, monIndex, totalCount, false);

        if (totalCount == 0) {
            return (extraData, true); // Remove effect entirely
        }

        return (_packExtraData(totalCount, tempCount), false);
    }
}
