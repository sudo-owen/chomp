// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName, StatBoostFlag, StatBoostType} from "../Enums.sol";
import {StatBoostToApply, StatBoostUpdate} from "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";
import {IEffect} from "./IEffect.sol";

/**
 *  Usage Notes:
 *  Any given caller can mutate multiple stats, but only in one direction and by one boost percent. (However, the same boost can stack)
 *  If you wish to mutate the same state but in **multiple different ways** (e.g. scale ATK up by 50%, and then later by 25%), you should
 *  use a different key for each boost type, and it's up to the caller to manage the keys and clean them up when needed
 *
 *  Extra Data Layout:
 *  [ uint32 empty | uint32 scaledAtk | uint32 scaledDef | uint32 scaledSpAtk | uint32 scaledSpDef | uint32 scaledSpeed ] <-- uint256
 *  [ uint176 key | uint80 (atk: [uint8 boostPercent | uint7 boostCount | uint1 isMultiply] | def: [uint8 boostPercent | uint7 boostCount | uint1 isMultiply] | ... )] <-- uint256 array for temporary boosts
 *  [ same as above ] <-- uint256 array for permanent boosts
 *
 *   adding a boost:
 *   - check if key is already in array
 *   - if so, update value in array
 *   - otherwise, add to array
 *   - recalculate stat amount for modified stat
 *   - update mon state
 *
 *   removing a boost:
 *   - check for key in array
 *   - if so, remove value from array
 *   - recalculate stat amount for modified stat
 *   - update mon state
 *
 *   removing all temporary boosts:
 *   - calculate total for each stat given by the temporary boosts
 *   - clear array
 *   - recalculate stat amount for modified stats
 *   - update mon states
 */

contract StatBoosts is BasicEffect {
    uint256 public constant DENOM = 100;

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
    function onMonSwitchOut(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        (uint256 activeBoostsSnapshot, uint256[] memory tempBoosts, uint256[] memory permBoosts) = _decodeExtraData(extraData);
        if (tempBoosts.length > 0) {
            tempBoosts = new uint256[](0);
            // Recalculate the stat boosts without the temporary boosts
            (uint256 newBoostsSnapshot, StatBoostUpdate[] memory statBoostUpdates) =
                _calculateUpdatedStatBoosts(targetIndex, monIndex, activeBoostsSnapshot, new uint256[](0), permBoosts);
            _applyStatBoostUpdates(targetIndex, monIndex, statBoostUpdates);
            bytes memory newExtraData = _encodeExtraData(newBoostsSnapshot, tempBoosts, permBoosts);
            return (newExtraData, false);
        }
        return (extraData, false);
    }

    // Each stat boost is packed and unpacked as:
    // [uint176 key | uint80 (atk: [uint8 boostPercent | uint7 boostCount | uint1 isMultiply] | def: [uint8 boostPercent | uint7 boostCount | uint1 isMultiply] | ... )]
    // Assumes that boostPercents is length 5, and boostCounts and isMultiply are length 5
    function _packBoostInstance(
        uint176 key,
        uint8[] memory boostPercents,
        uint8[] memory boostCounts,
        bool[] memory isMultiply
    ) internal pure returns (uint256) {
        uint256 packedBoostInstance = uint256(key) << 80;
        for (uint256 i = 0; i < boostPercents.length; i++) {
            uint256 offset = i * 16;
            uint256 boostInstance =
                (uint256(boostPercents[i]) << 8) | (uint256(boostCounts[i]) << 1) | (isMultiply[i] ? 1 : 0);
            packedBoostInstance |= boostInstance << offset;
        }
        return packedBoostInstance;
    }

    // Takes in an array of stat boosts (not for every stat)
    function _packBoostInstance(uint176 key, StatBoostToApply[] memory statBoostsToApply)
        internal
        pure
        returns (uint256)
    {
        uint8[] memory boostPercents = new uint8[](5);
        uint8[] memory boostCounts = new uint8[](5);
        bool[] memory isMultiply = new bool[](5);
        for (uint256 i = 0; i < statBoostsToApply.length; i++) {
            boostPercents[uint8(statBoostsToApply[i].stat)] = statBoostsToApply[i].boostPercent;
            boostCounts[uint8(statBoostsToApply[i].stat)] = 1;
            isMultiply[uint8(statBoostsToApply[i].stat)] = statBoostsToApply[i].boostType == StatBoostType.Multiply;
        }
        return _packBoostInstance(key, boostPercents, boostCounts, isMultiply);
    }

    function _unpackBoostInstance(uint256 packedBoostInstance)
        internal
        pure
        returns (uint176 key, uint8[] memory boostPercents, uint8[] memory boostCounts, bool[] memory isMultiply)
    {
        key = uint176(packedBoostInstance >> 80);
        boostPercents = new uint8[](5);
        boostCounts = new uint8[](5);
        isMultiply = new bool[](5);
        for (uint256 i = 0; i < 5; i++) {
            uint256 offset = i * 16;
            uint256 boostInstance = (packedBoostInstance >> offset) & 0xFFFF;
            uint8 boostPercent = uint8(boostInstance >> 8);
            uint8 boostCount = uint8((boostInstance >> 1) & 0x7F);
            bool isMultiplyFlag = (boostInstance & 0x1) == 1;
            boostPercents[i] = boostPercent;
            boostCounts[i] = boostCount;
            isMultiply[i] = isMultiplyFlag;
        }
        return (key, boostPercents, boostCounts, isMultiply);
    }

    function _generateKey(uint256 targetIndex, uint256 monIndex, address caller, string memory salt)
        internal
        pure
        returns (uint176)
    {
        return uint176(uint256(keccak256(abi.encode(targetIndex, monIndex, caller, salt))));
    }

    function _findExistingStatBoosts(uint256 targetIndex, uint256 monIndex)
        internal
        view
        returns (bool found, uint256 effectIndex, bytes memory extraData)
    {
        (IEffect[] memory effects, bytes[] memory extraDatas) =
            ENGINE.getEffects(ENGINE.battleKeyForWrite(), targetIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i]) == address(this)) {
                return (true, i, extraDatas[i]);
            }
        }
        return (false, 0, "");
    }

    function _encodeExtraData(uint256 boostsSnapshot, uint256[] memory tempBoosts, uint256[] memory permBoosts)
        internal
        pure
        returns (bytes memory extraData)
    {
        return abi.encode(boostsSnapshot, tempBoosts, permBoosts);
    }

    function _decodeExtraData(bytes memory extraData)
        internal
        pure
        returns (uint256 boostsSnapshot, uint256[] memory tempBoosts, uint256[] memory permBoosts)
    {
        return abi.decode(extraData, (uint256, uint256[], uint256[]));
    }

    function _packBoostSnapshot(uint32[] memory unpackedSnapshot) internal pure returns (uint256) {
        return (uint256(unpackedSnapshot[0]) << 160) | (uint256(unpackedSnapshot[1]) << 128)
            | (uint256(unpackedSnapshot[2]) << 96) | (uint256(unpackedSnapshot[3]) << 64)
            | (uint256(unpackedSnapshot[4]) << 32);
    }

    /*
        Returns what the scaled stat would be, assuming only the stat boosts were applied
        If an existing stat is 0, we default to the mon's original value
    */
    function _unpackBoostSnapshot(uint256 playerIndex, uint256 monIndex, uint256 boostSnapshot)
        internal
        view
        returns (uint32[] memory snapshotPerStat)
    {
        snapshotPerStat = new uint32[](5);
        snapshotPerStat[0] = uint32((boostSnapshot >> 160) & 0xFFFFFFFF);
        snapshotPerStat[1] = uint32((boostSnapshot >> 128) & 0xFFFFFFFF);
        snapshotPerStat[2] = uint32((boostSnapshot >> 96) & 0xFFFFFFFF);
        snapshotPerStat[3] = uint32((boostSnapshot >> 64) & 0xFFFFFFFF);
        snapshotPerStat[4] = uint32((boostSnapshot >> 32) & 0xFFFFFFFF);
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
        stats[0] = ENGINE.getMonValueForBattle(battleKey, playerIndex, monIndex, MonStateIndexName.Attack);
        stats[1] = ENGINE.getMonValueForBattle(battleKey, playerIndex, monIndex, MonStateIndexName.Defense);
        stats[2] = ENGINE.getMonValueForBattle(battleKey, playerIndex, monIndex, MonStateIndexName.SpecialAttack);
        stats[3] = ENGINE.getMonValueForBattle(battleKey, playerIndex, monIndex, MonStateIndexName.SpecialDefense);
        stats[4] = ENGINE.getMonValueForBattle(battleKey, playerIndex, monIndex, MonStateIndexName.Speed);
        return stats;
    }

    function _calculateUpdatedStatBoosts(
        uint256 playerIndex,
        uint256 monIndex,
        uint256 prevBoostsSnapshot,
        uint256[] memory tempBoosts,
        uint256[] memory permBoosts
    ) internal view returns (uint256, StatBoostUpdate[] memory) {
        uint32[] memory oldBoostedStats = _unpackBoostSnapshot(playerIndex, monIndex, prevBoostsSnapshot);
        uint32[] memory newBoostedStats = new uint32[](5);
        {
            uint32[] memory stats = _getMonStatSubset(playerIndex, monIndex);
            uint32[] memory numBoostsPerStat = new uint32[](5);
            uint256[] memory accumulatedNumeratorPerStat = new uint256[](5);
            uint256[][] memory allBoosts = new uint256[][](2);
            allBoosts[0] = tempBoosts;
            allBoosts[1] = permBoosts;
            // Go through all the boosts (temporary and permanent) and calculate the new values
            for (uint256 i; i < allBoosts.length; i++) {
                for (uint256 j; j < allBoosts[i].length; j++) {
                    (, uint8[] memory boostPercents, uint8[] memory boostCounts, bool[] memory isMultiply) =
                        _unpackBoostInstance(allBoosts[i][j]);
                    // For each boost calculate the updated scaled stat
                    // We are assuming that k tracks the same stat ordering as the other stat arrays
                    for (uint256 k; k < boostPercents.length; k++) {
                        if (boostCounts[k] == 0) {
                            continue;
                        }
                        uint256 boostPercent = boostPercents[k];
                        uint256 existingStatValue =
                            (accumulatedNumeratorPerStat[k] == 0) ? stats[k] : accumulatedNumeratorPerStat[k];
                        uint256 scalingFactor = isMultiply[k] ? DENOM + boostPercent : DENOM - boostPercent;
                        uint8 numTimesToBoost = boostCounts[k];
                        accumulatedNumeratorPerStat[k] = existingStatValue * (scalingFactor ** numTimesToBoost);
                        numBoostsPerStat[k] += numTimesToBoost;
                    }
                }
            }
            // Go through all accumulated values and divide by the number of boosts to calculate the new value
            for (uint256 i; i < accumulatedNumeratorPerStat.length; i++) {
                if (numBoostsPerStat[i] > 0) {
                    newBoostedStats[i] = uint32(accumulatedNumeratorPerStat[i] / (DENOM ** numBoostsPerStat[i]));
                } else {
                    newBoostedStats[i] = oldBoostedStats[i];
                }
            }
        }
        // Return the deltas from the previous calculation
        StatBoostUpdate[] memory statBoostUpdates = new StatBoostUpdate[](oldBoostedStats.length);
        for (uint256 i; i < oldBoostedStats.length; i++) {
            statBoostUpdates[i] =
                StatBoostUpdate(_statBoostIndexToMonStateIndex(i), oldBoostedStats[i], newBoostedStats[i]);
        }
        return (_packBoostSnapshot(newBoostedStats), statBoostUpdates);
    }

    function _applyStatBoostUpdates(uint256 targetIndex, uint256 monIndex, StatBoostUpdate[] memory statBoostUpdates)
        internal
    {
        for (uint256 i; i < statBoostUpdates.length; i++) {
            int32 delta = int32(statBoostUpdates[i].newStat) - int32(statBoostUpdates[i].oldStat);
            if (delta != 0) {
                ENGINE.updateMonState(targetIndex, monIndex, statBoostUpdates[i].stat, delta);
            }
        }
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
        /**
         * Go through each new boost and check if the existing boost percent has a value (we default to the original boost percent)
         * If so, we simply update the existing boost count
         * Otherwise, we add the new boost to the array
         */
        mergedBoostPercents = existingBoostPercents;
        mergedBoostCounts = existingBoostCounts;
        mergedIsMultiply = existingIsMultiply;
        for (uint256 i; i < newBoostsToApply.length; i++) {
            uint256 statIndex = uint256(newBoostsToApply[i].stat);
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

    function addStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag
    ) public {
        // By default we assume one stat boost ID per caller
        uint176 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function addKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        string memory keyToUse
    ) public {
        uint176 key = _generateKey(targetIndex, monIndex, msg.sender, keyToUse);
        _addStatBoostsWithKey(targetIndex, monIndex, statBoostsToApply, boostFlag, key);
    }

    function _addStatBoostsWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostToApply[] memory statBoostsToApply,
        StatBoostFlag boostFlag,
        uint176 key
    ) internal {
        uint256 activeBoostsSnapshot;
        uint256[] memory tempBoosts;
        uint256[] memory permBoosts;
        /*
        - go through all effects, check if stat boosts is already applied
        - if so, go through all keys and check if our key is already there
        - if so, update the boost percent and recalculate
        - otherwise, add to the array and recalculate
        - otherwise, add new effect and recalculate
        */
        (bool found, uint256 effectIndex, bytes memory extraData) = _findExistingStatBoosts(targetIndex, monIndex);
        if (found) {
            (activeBoostsSnapshot, tempBoosts, permBoosts) = _decodeExtraData(extraData);
            bool boostWithKeyAlreadyExists = false;
            uint256[] memory targetArray = boostFlag == StatBoostFlag.Temp ? tempBoosts : permBoosts;
            for (uint256 i; i < targetArray.length; i++) {
                (
                    uint176 existingKey,
                    uint8[] memory existingBoostPercents,
                    uint8[] memory existingBoostCounts,
                    bool[] memory existingIsMultiply
                ) = _unpackBoostInstance(targetArray[i]);
                if (existingKey == key) {
                    // Update the existing boost instance with the new boost percent and stat index
                    (
                        uint8[] memory mergedBoostPercents,
                        uint8[] memory mergedBoostCounts,
                        bool[] memory mergedIsMultiply
                    ) = _mergeExistingAndNewBoosts(
                        existingBoostPercents, existingBoostCounts, existingIsMultiply, statBoostsToApply
                    );
                    targetArray[i] =
                        _packBoostInstance(existingKey, mergedBoostPercents, mergedBoostCounts, mergedIsMultiply);
                    boostWithKeyAlreadyExists = true;
                    break;
                }
            }
            if (!boostWithKeyAlreadyExists) {
                uint256[] memory newArray = new uint256[](targetArray.length + 1);
                for (uint256 i = 0; i < targetArray.length; i++) {
                    newArray[i] = targetArray[i];
                }
                newArray[targetArray.length] = _packBoostInstance(key, statBoostsToApply);
                if (boostFlag == StatBoostFlag.Temp) {
                    tempBoosts = newArray;
                } else {
                    permBoosts = newArray;
                }
            }
        } else {
            tempBoosts = new uint256[](0);
            permBoosts = new uint256[](0);
            uint256 packedBoostInstance = _packBoostInstance(key, statBoostsToApply);
            if (boostFlag == StatBoostFlag.Temp) {
                tempBoosts = new uint256[](1);
                tempBoosts[0] = packedBoostInstance;
            } else {
                permBoosts = new uint256[](1);
                permBoosts[0] = packedBoostInstance;
            }
        }
        (uint256 newBoostsSnapshot, StatBoostUpdate[] memory statBoostUpdates) =
            _calculateUpdatedStatBoosts(targetIndex, monIndex, activeBoostsSnapshot, tempBoosts, permBoosts);
        bytes memory newExtraData = _encodeExtraData(newBoostsSnapshot, tempBoosts, permBoosts);
        if (found) {
            ENGINE.editEffect(targetIndex, monIndex, effectIndex, newExtraData);
        } else {
            ENGINE.addEffect(targetIndex, monIndex, IEffect(address(this)), newExtraData);
        }
        _applyStatBoostUpdates(targetIndex, monIndex, statBoostUpdates);
    }

    function removeStatBoosts(uint256 targetIndex, uint256 monIndex, StatBoostFlag boostFlag) public {
        uint176 key = _generateKey(targetIndex, monIndex, msg.sender, name());
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function removeKeyedStatBoosts(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostFlag boostFlag,
        string memory stringToUse
    ) public {
        uint176 key = _generateKey(targetIndex, monIndex, msg.sender, stringToUse);
        _removeStatBoostsWithKey(targetIndex, monIndex, key, boostFlag);
    }

    function _removeStatBoostsWithKey(uint256 targetIndex, uint256 monIndex, uint176 key, StatBoostFlag boostFlag)
        internal
    {
        uint256 activeBoostsSnapshot;
        uint256[] memory tempBoosts;
        uint256[] memory permBoosts;
        (bool found, uint256 effectIndex, bytes memory extraData) = _findExistingStatBoosts(targetIndex, monIndex);
        if (found) {
            (activeBoostsSnapshot, tempBoosts, permBoosts) = _decodeExtraData(extraData);
            uint256[] memory targetArray = boostFlag == StatBoostFlag.Temp ? tempBoosts : permBoosts;
            for (uint256 i; i < targetArray.length; i++) {
                (uint176 existingKey,,,) = _unpackBoostInstance(targetArray[i]);
                if (existingKey == key) {
                    // Remove the boost instance from the array
                    uint256[] memory newArray = new uint256[](targetArray.length - 1);
                    for (uint256 j = 0; j < i; j++) {
                        newArray[j] = targetArray[j];
                    }
                    for (uint256 j = i + 1; j < targetArray.length; j++) {
                        newArray[j - 1] = targetArray[j];
                    }
                    // Update the target array
                    if (boostFlag == StatBoostFlag.Temp) {
                        tempBoosts = newArray;
                    } else {
                        permBoosts = newArray;
                    }
                    // Recalculate the stat boosts
                    (uint256 newBoostsSnapshot, StatBoostUpdate[] memory statBoostUpdates) =
                        _calculateUpdatedStatBoosts(targetIndex, monIndex, activeBoostsSnapshot, tempBoosts, permBoosts);
                    // Save the new extra data
                    bytes memory newExtraData = _encodeExtraData(newBoostsSnapshot, tempBoosts, permBoosts);
                    ENGINE.editEffect(targetIndex, monIndex, effectIndex, newExtraData);
                    _applyStatBoostUpdates(targetIndex, monIndex, statBoostUpdates);
                    break;
                }
            }
        }
    }

    // function removeAllTempBoosts(uint256 targetIndex, uint256 monIndex) public {
    //     if (found) {
    //         (uint256 activeBoostsSnapshot,, uint256[] memory permBoosts) =
    //             _decodeExtraData(extraData);
    //         bytes memory newExtraData = _encodeExtraData(activeBoostsSnapshot, new uint256[](0), permBoosts);
    //         ENGINE.editEffect(targetIndex, monIndex, effectIndex, newExtraData);
    //         // Recalculate the stat boosts
    //         (, StatBoostUpdate[] memory statBoostUpdates) =
    //             _calculateUpdatedStatBoosts(targetIndex, monIndex, activeBoostsSnapshot, new uint256[](0), permBoosts);
    //         _applyStatBoostUpdates(targetIndex, monIndex, statBoostUpdates);
    //     }
    // }
}
