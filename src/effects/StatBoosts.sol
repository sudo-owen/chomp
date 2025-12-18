// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName, StatBoostFlag, StatBoostType} from "../Enums.sol";
import {EffectInstance, MonStats, StatBoostToApply} from "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";
import {IEffect} from "./IEffect.sol";

/**
 * Usage Notes:
 *  - Each effect instance stores ONE stat boost (1 stat per effect)
 *  - Multiple stats = multiple effect instances
 *  - Snapshot (aggregated multipliers) stored in globalKV
 *
 *  Extra Data Layout (uint96 - fits in single slot with address):
 *  [1 bit isPerm | 3 bits statIndex | 8 bits boostPercent | 7 bits boostCount | 1 bit isMultiply | 76 bits key]
 *
 *  Snapshot stored in globalKV with key: keccak256(targetIndex, monIndex, address(this))
 *  Snapshot layout (uint192):
 *  [32 atk | 32 def | 32 spatk | 32 spdef | 32 speed | 32 empty]
 */

contract StatBoosts is BasicEffect {
    uint256 public constant DENOM = 100;

    // New layout for uint96: [1 isPerm | 3 statIndex | 8 boostPercent | 7 boostCount | 1 isMultiply | 76 key]
    uint256 private constant PERM_FLAG_OFFSET = 95;      // bit 95 (top bit of uint96)
    uint256 private constant STAT_INDEX_OFFSET = 92;     // bits 92-94 (3 bits)
    uint256 private constant BOOST_PERCENT_OFFSET = 84;  // bits 84-91 (8 bits)
    uint256 private constant BOOST_COUNT_OFFSET = 77;    // bits 77-83 (7 bits)
    uint256 private constant IS_MULTIPLY_OFFSET = 76;    // bit 76
    uint256 private constant KEY_MASK = (1 << 76) - 1;   // bits 0-75 (76 bits)

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
        return (uint256(data) >> PERM_FLAG_OFFSET) & 1 != 0;
    }

    function _snapshotKey(uint256 targetIndex, uint256 monIndex) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, address(this)));
    }

    // Pack single-stat boost data
    // Layout: [1 isPerm | 3 statIndex | 8 boostPercent | 7 boostCount | 1 isMultiply | 76 key]
    function _packBoostData(
        uint256 key,
        bool isPerm,
        uint8 statIndex,
        uint8 boostPercent,
        uint8 boostCount,
        bool isMultiply
    ) internal pure returns (bytes32) {
        uint256 packed = 0;
        if (isPerm) packed |= uint256(1) << PERM_FLAG_OFFSET;
        packed |= uint256(statIndex & 0x7) << STAT_INDEX_OFFSET;
        packed |= uint256(boostPercent) << BOOST_PERCENT_OFFSET;
        packed |= uint256(boostCount & 0x7F) << BOOST_COUNT_OFFSET;
        if (isMultiply) packed |= uint256(1) << IS_MULTIPLY_OFFSET;
        packed |= (key & KEY_MASK);
        return bytes32(packed);
    }

    // Unpack single-stat boost data
    function _unpackBoostData(bytes32 data)
        internal
        pure
        returns (
            bool isPerm,
            uint256 key,
            uint8 statIndex,
            uint8 boostPercent,
            uint8 boostCount,
            bool isMultiply
        )
    {
        uint256 packed = uint256(data);
        isPerm = (packed >> PERM_FLAG_OFFSET) & 1 != 0;
        statIndex = uint8((packed >> STAT_INDEX_OFFSET) & 0x7);
        boostPercent = uint8((packed >> BOOST_PERCENT_OFFSET) & 0xFF);
        boostCount = uint8((packed >> BOOST_COUNT_OFFSET) & 0x7F);
        isMultiply = (packed >> IS_MULTIPLY_OFFSET) & 1 != 0;
        key = packed & KEY_MASK;
    }

    // Extract just key and isPerm for matching (cheaper than full unpack)
    function _unpackBoostHeader(bytes32 data) internal pure returns (bool isPerm, uint256 key, uint8 statIndex) {
        uint256 packed = uint256(data);
        isPerm = (packed >> PERM_FLAG_OFFSET) & 1 != 0;
        statIndex = uint8((packed >> STAT_INDEX_OFFSET) & 0x7);
        key = packed & KEY_MASK;
    }

    function _generateKey(uint256 targetIndex, uint256 monIndex, address caller, string memory salt)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(targetIndex, monIndex, caller, salt))) & KEY_MASK;
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

    function _packBoostSnapshot(uint32[5] memory unpackedSnapshot) internal pure returns (uint192) {
        return uint192(
            (uint256(unpackedSnapshot[0]) << 160) | (uint256(unpackedSnapshot[1]) << 128)
                | (uint256(unpackedSnapshot[2]) << 96) | (uint256(unpackedSnapshot[3]) << 64)
                | (uint256(unpackedSnapshot[4]) << 32)
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

    // Mapping: Attack(3)->0, Defense(4)->1, SpecialAttack(5)->2, SpecialDefense(6)->3, Speed(2)->4
    function _monStateIndexToStatBoostIndex(MonStateIndexName statIndex) internal pure returns (uint8) {
        uint256 idx = uint256(statIndex);
        if (idx == 2) return 4;
        return uint8(idx - 3);
    }

    function _statBoostIndexToMonStateIndex(uint8 statBoostIndex) internal pure returns (MonStateIndexName) {
        if (statBoostIndex == 4) return MonStateIndexName.Speed;
        return MonStateIndexName(statBoostIndex + 3);
    }

    function _getMonStatSubset(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) internal view returns (uint32[5] memory stats) {
        MonStats memory monStats = ENGINE.getMonStatsForBattle(battleKey, playerIndex, monIndex);
        stats[0] = monStats.attack;
        stats[1] = monStats.defense;
        stats[2] = monStats.specialAttack;
        stats[3] = monStats.specialDefense;
        stats[4] = monStats.speed;
    }

    // Apply stat deltas from pre-aggregated boost data
    function _applyStatsFromAggregatedData(
        bytes32 battleKey,
        uint256 targetIndex,
        uint256 monIndex,
        uint32[5] memory baseStats,
        uint32[5] memory numBoostsPerStat,
        uint256[5] memory accumulatedNumeratorPerStat
    ) internal {
        bytes32 snapshotKey = _snapshotKey(targetIndex, monIndex);
        uint192 prevSnapshot = ENGINE.getGlobalKV(battleKey, snapshotKey);
        uint32[5] memory oldBoostedStats = _unpackBoostSnapshot(prevSnapshot, baseStats);

        uint32[5] memory newBoostedStats;
        for (uint256 i = 0; i < 5; i++) {
            if (numBoostsPerStat[i] > 0) {
                newBoostedStats[i] = uint32(accumulatedNumeratorPerStat[i] / _denomPower(numBoostsPerStat[i]));
            } else {
                newBoostedStats[i] = baseStats[i];
            }
        }

        for (uint256 i = 0; i < 5; i++) {
            int32 delta = int32(newBoostedStats[i]) - int32(oldBoostedStats[i]);
            if (delta != 0) {
                ENGINE.updateMonState(targetIndex, monIndex, _statBoostIndexToMonStateIndex(uint8(i)), delta);
            }
        }

        ENGINE.setGlobalKV(snapshotKey, _packBoostSnapshot(newBoostedStats));
    }

    // Accumulate a single stat boost into running totals
    function _accumulateSingleBoost(
        uint32[5] memory baseStats,
        uint8 statIndex,
        uint8 boostPercent,
        uint8 boostCount,
        bool isMultiply,
        uint32[5] memory numBoostsPerStat,
        uint256[5] memory accumulatedNumeratorPerStat
    ) internal pure {
        if (boostCount == 0) return;
        uint256 existingStatValue = (accumulatedNumeratorPerStat[statIndex] == 0)
            ? baseStats[statIndex]
            : accumulatedNumeratorPerStat[statIndex];
        uint256 scalingFactor = isMultiply ? DENOM + boostPercent : DENOM - boostPercent;
        accumulatedNumeratorPerStat[statIndex] = existingStatValue * (scalingFactor ** boostCount);
        numBoostsPerStat[statIndex] += boostCount;
    }

    // Recalculate stats by iterating through all StatBoosts effects
    function _recalculateAndApplyStats(uint256 targetIndex, uint256 monIndex, bool excludeTempBoosts) internal {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects,) = ENGINE.getEffects(battleKey, targetIndex, monIndex);

        uint32[5] memory stats = _getMonStatSubset(battleKey, targetIndex, monIndex);
        uint32[5] memory numBoostsPerStat;
        uint256[5] memory accumulatedNumeratorPerStat;

        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                (bool isPerm, , uint8 statIndex, uint8 boostPercent, uint8 boostCount, bool isMultiply) =
                    _unpackBoostData(bytes32(uint256(effects[i].data)));
                if (excludeTempBoosts && !isPerm) continue;
                _accumulateSingleBoost(stats, statIndex, boostPercent, boostCount, isMultiply, numBoostsPerStat, accumulatedNumeratorPerStat);
            }
        }

        _applyStatsFromAggregatedData(battleKey, targetIndex, monIndex, stats, numBoostsPerStat, accumulatedNumeratorPerStat);
    }

    function addStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag
    ) public {
        uint256 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function addKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        string memory keyToUse
    ) public {
        uint256 key = _generateKey(targetIndex, monIndex, msg.sender, keyToUse);
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function _addStatBoostsWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        uint256 key
    ) internal {
        bool isPerm = boostFlag == StatBoostFlag.Perm;
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(battleKey, targetIndex, monIndex);
        uint32[5] memory baseStats = _getMonStatSubset(battleKey, targetIndex, monIndex);

        uint32[5] memory numBoostsPerStat;
        uint256[5] memory accumulatedNumeratorPerStat;

        // Track which stats we're adding boosts for and their existing effect indices
        bool[5] memory statNeedsBoost;
        bool[5] memory foundExistingEffect;
        uint256[5] memory existingEffectIndices;
        uint8[5] memory existingBoostCounts;

        // Mark which stats we need to boost
        for (uint256 i = 0; i < statBoostsToApply.length; i++) {
            uint8 statIndex = _monStateIndexToStatBoostIndex(statBoostsToApply[i].stat);
            statNeedsBoost[statIndex] = true;
        }

        // Single pass: find existing effects with matching key+stat AND aggregate all effects
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                (bool effIsPerm, uint256 existingKey, uint8 statIndex, uint8 boostPercent, uint8 boostCount, bool isMultiply) =
                    _unpackBoostData(bytes32(uint256(effects[i].data)));

                // Check if this is an effect we're looking for (same key, isPerm, and stat we want to boost)
                if (existingKey == key && effIsPerm == isPerm && statNeedsBoost[statIndex]) {
                    foundExistingEffect[statIndex] = true;
                    existingEffectIndices[statIndex] = indices[i];
                    existingBoostCounts[statIndex] = boostCount;
                    // Don't aggregate this one - we'll add the updated version
                    continue;
                }

                // Aggregate this effect
                _accumulateSingleBoost(baseStats, statIndex, boostPercent, boostCount, isMultiply, numBoostsPerStat, accumulatedNumeratorPerStat);
            }
        }

        // Now add/update effects for each stat boost
        for (uint256 i = 0; i < statBoostsToApply.length; i++) {
            uint8 statIndex = _monStateIndexToStatBoostIndex(statBoostsToApply[i].stat);
            uint8 boostPercent = statBoostsToApply[i].boostPercent;
            bool isMultiply = statBoostsToApply[i].boostType == StatBoostType.Multiply;

            uint8 newBoostCount;
            if (foundExistingEffect[statIndex]) {
                // Increment existing boost count
                newBoostCount = existingBoostCounts[statIndex] + 1;
                bytes32 newData = _packBoostData(key, isPerm, statIndex, boostPercent, newBoostCount, isMultiply);
                ENGINE.editEffect(targetIndex, monIndex, existingEffectIndices[statIndex], newData);
            } else {
                // Add new effect
                newBoostCount = 1;
                bytes32 newData = _packBoostData(key, isPerm, statIndex, boostPercent, newBoostCount, isMultiply);
                ENGINE.addEffect(targetIndex, monIndex, IEffect(address(this)), newData);
            }

            // Add this boost to aggregation
            _accumulateSingleBoost(baseStats, statIndex, boostPercent, newBoostCount, isMultiply, numBoostsPerStat, accumulatedNumeratorPerStat);
        }

        // Apply stats using computed aggregation
        _applyStatsFromAggregatedData(battleKey, targetIndex, monIndex, baseStats, numBoostsPerStat, accumulatedNumeratorPerStat);
    }

    function removeStatBoosts(uint256 targetIndex, uint256 monIndex, StatBoostFlag boostFlag) public {
        uint256 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function removeKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostFlag boostFlag,
        string memory stringToUse
    ) public {
        uint256 key = _generateKey(targetIndex, monIndex, msg.sender, stringToUse);
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function _removeStatBoostsWithKey(uint256 targetIndex, uint256 monIndex, uint256 key, StatBoostFlag boostFlag) internal {
        bool isPerm = boostFlag == StatBoostFlag.Perm;
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(battleKey, targetIndex, monIndex);
        uint32[5] memory baseStats = _getMonStatSubset(battleKey, targetIndex, monIndex);

        uint32[5] memory numBoostsPerStat;
        uint256[5] memory accumulatedNumeratorPerStat;

        // Collect indices to remove (iterate in reverse order for safe removal)
        uint256[] memory indicesToRemove = new uint256[](effects.length);
        uint256 removeCount = 0;

        // Single pass: find matching effects AND aggregate non-matching ones
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                (bool effIsPerm, uint256 existingKey, uint8 statIndex, uint8 boostPercent, uint8 boostCount, bool isMultiply) =
                    _unpackBoostData(bytes32(uint256(effects[i].data)));

                if (existingKey == key && effIsPerm == isPerm) {
                    // Mark for removal
                    indicesToRemove[removeCount] = indices[i];
                    removeCount++;
                    continue;
                }

                // Aggregate this effect
                _accumulateSingleBoost(baseStats, statIndex, boostPercent, boostCount, isMultiply, numBoostsPerStat, accumulatedNumeratorPerStat);
            }
        }

        if (removeCount > 0) {
            // Remove effects (in reverse order to preserve indices)
            for (uint256 i = removeCount; i > 0; i--) {
                ENGINE.removeEffect(targetIndex, monIndex, indicesToRemove[i - 1]);
            }
            // Apply stats
            _applyStatsFromAggregatedData(battleKey, targetIndex, monIndex, baseStats, numBoostsPerStat, accumulatedNumeratorPerStat);
        }
    }

    /// @notice Clears all stat boosts for a mon and resets stats to base values
    function clearAllBoostsForMon(uint256 targetIndex, uint256 monIndex) external {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        (EffectInstance[] memory effects, uint256[] memory indices) = ENGINE.getEffects(battleKey, targetIndex, monIndex);
        uint32[5] memory baseStats = _getMonStatSubset(battleKey, targetIndex, monIndex);

        uint256 removeCount = 0;
        for (uint256 i = effects.length; i > 0; i--) {
            if (address(effects[i - 1].effect) == address(this)) {
                ENGINE.removeEffect(targetIndex, monIndex, indices[i - 1]);
                removeCount++;
            }
        }

        if (removeCount == 0) {
            return;
        }

        // Reset stats to base values
        uint32[5] memory numBoostsPerStat;
        uint256[5] memory accumulatedNumeratorPerStat;
        _applyStatsFromAggregatedData(battleKey, targetIndex, monIndex, baseStats, numBoostsPerStat, accumulatedNumeratorPerStat);
    }
}
