// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName, StatBoostFlag, StatBoostType} from "../Enums.sol";
import {StatBoostUpdate} from "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";
import {IEffect} from "./IEffect.sol";

/**
 *  Extra Data:
 *  [ uint32 empty | uint32 scaledAtk | uint32 scaledDef | uint32 scaledSpAtk | uint32 scaledSpDef | uint32 scaledSpeed ] <-- uint256
 *  [ [ uintX empty | uint128 key | uint32 boostAmount | uint8 boostInfo (uint4 empty | uint3 statType | uint1 direction)] ] <-- uint256 array for temporary boosts
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

    function onMonSwitchOut(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        return ("", false);
    }

    // Each stat boost is packed and unpacked as:
    // [uint216 key | uint32 boostPercent | (uint7 statType | uint1 isMultiply)]
    function _packBoostInstance(uint216 key, uint32 boostPercent, MonStateIndexName stat, StatBoostType boostType)
        internal
        pure
        returns (uint256)
    {
        uint8 statType = uint8(stat);
        bool isMultiply = boostType == StatBoostType.Multiply;
        uint8 boostInfo = (statType << 1) | (isMultiply ? 1 : 0);
        return (uint256(key) << 40) | (uint256(boostPercent) << 8) | uint256(boostInfo);
    }

    function _unpackBoostInstance(uint256 packedBoostInstance)
        internal
        pure
        returns (uint216, uint32, MonStateIndexName, StatBoostType)
    {
        uint216 key = uint216(packedBoostInstance >> 40);
        uint32 boostPercent = uint32((packedBoostInstance >> 8) & 0xFFFFFFFF);
        uint8 statType = uint8((packedBoostInstance >> 1) & 0x7F);
        bool isMultiply = (packedBoostInstance & 0x1) == 1;
        return
            (key, boostPercent, MonStateIndexName(statType), isMultiply ? StatBoostType.Multiply : StatBoostType.Divide);
    }

    function _generateKey(uint256 targetIndex, uint256 monIndex, string memory salt) internal pure returns (uint216) {
        return uint216(uint256(keccak256(abi.encode(targetIndex, monIndex, salt))));
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
        returns (uint32[] memory)
    {
        uint32[] memory snapshotPerStat = new uint32[](5);
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
            // Go through all the boosts and calculate the new values
            for (uint256 i; i < allBoosts.length; i++) {
                for (uint256 j; j < allBoosts[i].length; j++) {
                    (, uint32 boostPercent, MonStateIndexName statIndex, StatBoostType boostType) =
                        _unpackBoostInstance(allBoosts[i][j]);
                    uint256 existingStatValue;
                    if (accumulatedNumeratorPerStat[_monStateIndexToStatBoostIndex(statIndex)] == 0) {
                        existingStatValue = stats[_monStateIndexToStatBoostIndex(statIndex)];
                    } else {
                        existingStatValue = accumulatedNumeratorPerStat[_monStateIndexToStatBoostIndex(statIndex)];
                    }
                    uint256 scalingFactor = DENOM;
                    if (boostType == StatBoostType.Multiply) {
                        scalingFactor = scalingFactor + boostPercent;
                    } else {
                        scalingFactor = scalingFactor - boostPercent;
                    }
                    accumulatedNumeratorPerStat[_monStateIndexToStatBoostIndex(statIndex)] =
                        existingStatValue * scalingFactor;
                    numBoostsPerStat[_monStateIndexToStatBoostIndex(statIndex)]++;
                }
            }
            // Go through all accumulated values and divide by the number of boosts
            for (uint256 i; i < accumulatedNumeratorPerStat.length; i++) {
                if (numBoostsPerStat[i] > 0) {
                    newBoostedStats[i] = uint32(accumulatedNumeratorPerStat[i] / (DENOM ** numBoostsPerStat[i]));
                }
            }
        }
        StatBoostUpdate[] memory statBoostUpdates = new StatBoostUpdate[](oldBoostedStats.length);
        for (uint256 i; i < oldBoostedStats.length; i++) {
            statBoostUpdates[i] = StatBoostUpdate(_statBoostIndexToMonStateIndex(i), oldBoostedStats[i], newBoostedStats[i]);
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

    function addStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        MonStateIndexName stateIndex,
        uint32 boostPercent,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {
        // By default we assume one stat boost ID per caller
        uint216 key = _generateKey(targetIndex, monIndex, name());
        _addStatBoostWithKey(targetIndex, monIndex, stateIndex, boostPercent, boostType, boostFlag, key);
    }

    function addKeyedStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        MonStateIndexName stateIndex,
        uint32 boostPercent,
        StatBoostType boostType,
        StatBoostFlag boostFlag,
        string memory salt
    ) public {
        uint216 key = _generateKey(targetIndex, monIndex, salt);
        _addStatBoostWithKey(targetIndex, monIndex, stateIndex, boostPercent, boostType, boostFlag, key);
    }

    function _addStatBoostWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        MonStateIndexName stateIndex,
        uint32 boostPercent,
        StatBoostType boostType,
        StatBoostFlag boostFlag,
        uint216 key
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

            // bool boostWithKeyAlreadyExists = false;
            // uint256[] memory targetArray = boostFlag == StatBoostFlag.Temp ? tempBoosts : permBoosts;
            // for (uint256 i; i < targetArray.length; i++) {
            //     (uint216 existingKey, uint32 existingBoostPercent,,) = _unpackBoostInstance(targetArray[i]);
            //     if (existingKey == key) {
            //         targetArray[i] =
            //             _packBoostInstance(key, uint32(boostPercent), MonStateIndexName(statIndex), boostType);
            //         boostWithKeyAlreadyExists = true;
            //         break;
            //     }
            // }

            // If not found, append
            // if (!keyFound) {
            //     uint256[] memory newArray = new uint256[](targetArray.length + 1);
            //     for (uint256 i = 0; i < targetArray.length; i++) {
            //         newArray[i] = targetArray[i];
            //     }
            //     newArray[targetArray.length] =
            //         _packBoostInstance(key, uint32(boostPercent), MonStateIndexName(statIndex), boostType);

            //     if (boostFlag == StatBoostFlag.Temp) {
            //         tempBoosts = newArray;
            //     } else {
            //         permBoosts = newArray;
            //     }
            // }


        } else {
            tempBoosts = new uint256[](0);
            permBoosts = new uint256[](0);
            uint256 packedBoostInstance =
                _packBoostInstance(key, boostPercent, stateIndex, boostType);
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

    function removeStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        MonStateIndexName stateIndex,
        uint32 boostPercent,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {}
}
