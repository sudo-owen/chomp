// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Enums.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";

/**
 Extra Data:
 [ uint32 empty | int32 atkBoost | int32 defBoost | int32 spAtkBoost | int32 spDefBoost | int32 spdBoost ] <-- uint256
 [ [ uintX empty | uint160 key | uint32 boostAmount | uint8 boostInfo (uint4 empty | uint3 statType | uint1 direction)] ] <-- uint256 array for temporary boosts
 [ same as above ] <-- uint256 array for permanent boosts

  adding a boost:
  - check if key is already in array
  - if so, update value in array
  - otherwise, add to array
  - recalculate stat amount for modified stat
  - update mon state

  removing a boost:
  - check for key in array
  - if so, remove value from array
  - recalculate stat amount for modified stat
  - update mon state

  removing all temporary boosts:
  - calculate total for each stat given by the temporary boosts
  - clear array
  - recalculate stat amount for modified stats
  - update mon states
 */

contract StatBoosts is BasicEffect {
    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override returns (string memory) {
        return "Stat Boost";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return (r == EffectStep.OnMonSwitchOut || r == EffectStep.OnApply);
    }

    // ============ HELPER FUNCTIONS FOR PACKING/UNPACKING ============

    /**
     * Pack a boost instance into a uint256
     * Layout: [uint56 empty | uint160 key | uint32 boostAmount | uint8 boostInfo]
     * boostInfo: [uint4 empty | uint3 statType | uint1 direction]
     */
    function packBoostInstance(uint160 key, uint32 boostAmount, uint8 statType, bool isPositive)
        internal
        pure
        returns (uint256)
    {
        uint8 boostInfo = (statType << 1) | (isPositive ? 1 : 0);
        return (uint256(key) << 40) | (uint256(boostAmount) << 8) | uint256(boostInfo);
    }

    /**
     * Unpack a boost instance from a uint256
     * Returns: (key, boostAmount, statType, isPositive)
     */
    function unpackBoostInstance(uint256 packed)
        internal
        pure
        returns (uint160 key, uint32 boostAmount, uint8 statType, bool isPositive)
    {
        uint8 boostInfo = uint8(packed);
        boostAmount = uint32(packed >> 8);
        key = uint160(packed >> 40);

        isPositive = (boostInfo & 1) == 1;
        statType = (boostInfo >> 1) & 7;
    }

    /**
     * Get the net delta for a specific stat from the packed netDeltas uint256
     * Layout: [uint96 empty | int32 atkBoost | int32 defBoost | int32 spAtkBoost | int32 spDefBoost | int32 spdBoost]
     */
    function getNetDelta(uint256 netDeltas, uint8 statType) internal pure returns (int32) {
        // statType: 0=Atk, 1=Def, 2=SpAtk, 3=SpDef, 4=Spd
        uint256 shift = statType * 32;
        return int32(uint32(netDeltas >> shift));
    }

    /**
     * Set the net delta for a specific stat in the packed netDeltas uint256
     */
    function setNetDelta(uint256 netDeltas, uint8 statType, int32 delta) internal pure returns (uint256) {
        uint256 shift = statType * 32;
        uint256 mask = uint256(type(uint32).max) << shift;

        // Clear the old value and set the new one
        netDeltas = (netDeltas & ~mask) | (uint256(uint32(delta)) << shift);
        return netDeltas;
    }

    /**
     * Convert MonStateIndexName to statType (0-4)
     * Attack=3 -> 0, Defense=4 -> 1, SpecialAttack=5 -> 2, SpecialDefense=6 -> 3, Speed=2 -> 4
     */
    function monStateIndexToStatType(uint256 statIndex) internal pure returns (uint8) {
        if (statIndex == uint256(MonStateIndexName.Attack)) return 0;
        if (statIndex == uint256(MonStateIndexName.Defense)) return 1;
        if (statIndex == uint256(MonStateIndexName.SpecialAttack)) return 2;
        if (statIndex == uint256(MonStateIndexName.SpecialDefense)) return 3;
        if (statIndex == uint256(MonStateIndexName.Speed)) return 4;
        revert("Invalid stat index");
    }

    /**
     * Convert statType (0-4) to MonStateIndexName
     */
    function statTypeToMonStateIndex(uint8 statType) internal pure returns (MonStateIndexName) {
        if (statType == 0) return MonStateIndexName.Attack;
        if (statType == 1) return MonStateIndexName.Defense;
        if (statType == 2) return MonStateIndexName.SpecialAttack;
        if (statType == 3) return MonStateIndexName.SpecialDefense;
        if (statType == 4) return MonStateIndexName.Speed;
        revert("Invalid stat type");
    }

    /**
     * Generate a key for a boost
     */
    function generateKey(uint256 targetIndex, uint256 monIndex, address caller) internal pure returns (uint160) {
        return uint160(uint256(keccak256(abi.encode(targetIndex, monIndex, caller))));
    }

    // ============ EFFECT DATA MANAGEMENT ============

    /**
     * Get the storage key for net deltas
     */
    function getNetDeltasKey(uint256 targetIndex, uint256 monIndex) internal view returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, name(), "NET_DELTAS"));
    }

    /**
     * Get the storage key for array length
     */
    function getArrayLengthKey(uint256 targetIndex, uint256 monIndex, string memory arrayType)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(targetIndex, monIndex, name(), arrayType, "LENGTH"));
    }

    /**
     * Get the storage key for array element
     */
    function getArrayElementKey(uint256 targetIndex, uint256 monIndex, string memory arrayType, uint256 index)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(targetIndex, monIndex, name(), arrayType, index));
    }

    /**
     * Load effect data for a mon
     * Returns: (netDeltas, tempBoosts, permBoosts)
     */
    function loadEffectData(uint256 targetIndex, uint256 monIndex)
        internal
        view
        returns (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts)
    {
        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Load net deltas
        netDeltas = uint256(ENGINE.getGlobalKV(battleKey, getNetDeltasKey(targetIndex, monIndex)));

        // Load temp boosts array
        uint256 tempLength = uint256(ENGINE.getGlobalKV(battleKey, getArrayLengthKey(targetIndex, monIndex, "TEMP")));
        tempBoosts = new uint256[](tempLength);
        for (uint256 i = 0; i < tempLength; i++) {
            tempBoosts[i] = uint256(ENGINE.getGlobalKV(battleKey, getArrayElementKey(targetIndex, monIndex, "TEMP", i)));
        }

        // Load perm boosts array
        uint256 permLength = uint256(ENGINE.getGlobalKV(battleKey, getArrayLengthKey(targetIndex, monIndex, "PERM")));
        permBoosts = new uint256[](permLength);
        for (uint256 i = 0; i < permLength; i++) {
            permBoosts[i] = uint256(ENGINE.getGlobalKV(battleKey, getArrayElementKey(targetIndex, monIndex, "PERM", i)));
        }
    }

    /**
     * Save effect data for a mon
     */
    function saveEffectData(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 netDeltas,
        uint256[] memory tempBoosts,
        uint256[] memory permBoosts
    ) internal {
        bytes32 battleKey = ENGINE.battleKeyForWrite();

        // Save net deltas
        ENGINE.setGlobalKV(getNetDeltasKey(targetIndex, monIndex), bytes32(netDeltas));

        // Save temp boosts array
        ENGINE.setGlobalKV(getArrayLengthKey(targetIndex, monIndex, "TEMP"), bytes32(tempBoosts.length));
        for (uint256 i = 0; i < tempBoosts.length; i++) {
            ENGINE.setGlobalKV(getArrayElementKey(targetIndex, monIndex, "TEMP", i), bytes32(tempBoosts[i]));
        }

        // Save perm boosts array
        ENGINE.setGlobalKV(getArrayLengthKey(targetIndex, monIndex, "PERM"), bytes32(permBoosts.length));
        for (uint256 i = 0; i < permBoosts.length; i++) {
            ENGINE.setGlobalKV(getArrayElementKey(targetIndex, monIndex, "PERM", i), bytes32(permBoosts[i]));
        }
    }

    // ============ BOOST MANIPULATION ============

    /**
     * Calculate the total boost for a specific stat from an array of boost instances
     */
    function calculateTotalBoost(uint256[] memory boosts, uint8 statType) internal pure returns (int32 total) {
        for (uint256 i = 0; i < boosts.length; i++) {
            (, uint32 boostAmount, uint8 boostStatType, bool isPositive) = unpackBoostInstance(boosts[i]);

            if (boostStatType == statType) {
                if (isPositive) {
                    total += int32(boostAmount);
                } else {
                    total -= int32(boostAmount);
                }
            }
        }
    }

    /**
     * Find a boost by key in an array
     * Returns: (found, index)
     */
    function findBoost(uint256[] memory boosts, uint160 key) internal pure returns (bool found, uint256 index) {
        for (uint256 i = 0; i < boosts.length; i++) {
            (uint160 boostKey,,,) = unpackBoostInstance(boosts[i]);
            if (boostKey == key) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /**
     * Add or update a boost in an array
     * Returns: (updated array, old stat type if updating, was update)
     */
    function addOrUpdateBoost(uint256[] memory boosts, uint160 key, uint32 boostAmount, uint8 statType, bool isPositive)
        internal
        pure
        returns (uint256[] memory newBoosts, uint8 oldStatType, bool wasUpdate)
    {
        (bool found, uint256 index) = findBoost(boosts, key);

        if (found) {
            // Update existing boost
            (, , oldStatType,) = unpackBoostInstance(boosts[index]);
            newBoosts = boosts;
            newBoosts[index] = packBoostInstance(key, boostAmount, statType, isPositive);
            wasUpdate = true;
        } else {
            // Add new boost
            newBoosts = new uint256[](boosts.length + 1);
            for (uint256 i = 0; i < boosts.length; i++) {
                newBoosts[i] = boosts[i];
            }
            newBoosts[boosts.length] = packBoostInstance(key, boostAmount, statType, isPositive);
            wasUpdate = false;
        }
    }

    /**
     * Remove a boost from an array by key
     * Returns: (updated array, found, old stat type)
     */
    function removeBoost(uint256[] memory boosts, uint160 key)
        internal
        pure
        returns (uint256[] memory newBoosts, bool found, uint8 oldStatType)
    {
        (found, uint256 index) = findBoost(boosts, key);

        if (!found) {
            return (boosts, false, 0);
        }

        // Get the stat type before removing
        (,, oldStatType,) = unpackBoostInstance(boosts[index]);

        // Create new array without the boost
        newBoosts = new uint256[](boosts.length - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < boosts.length; i++) {
            if (i != index) {
                newBoosts[j] = boosts[i];
                j++;
            }
        }
    }

    // ============ PUBLIC INTERFACE ============

    /**
     * Add a stat boost with an auto-generated key
     */
    function addStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {
        uint160 key = generateKey(targetIndex, monIndex, msg.sender);
        addStatBoostWithKey(targetIndex, monIndex, statIndex, boostAmount, boostType, boostFlag, key);
    }

    /**
     * Add a stat boost with a custom key
     */
    function addStatBoostWithKey(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag,
        uint160 key
    ) public {
        require(boostFlag != StatBoostFlag.Existence, "Cannot use Existence flag");

        // Convert boostType and boostAmount to direction and absolute value
        bool isPositive = (boostType == StatBoostType.Multiply);
        uint32 absBoostAmount = uint32(boostAmount > 0 ? boostAmount : -boostAmount);

        uint8 statType = monStateIndexToStatType(statIndex);

        // First, ensure the effect exists on the mon
        bytes memory extraData = abi.encode(key, statType, absBoostAmount, isPositive, uint256(boostFlag));
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.addEffect(targetIndex, monIndex, this, extraData);
        ENGINE.setUpstreamCaller(address(0));
    }

    /**
     * Remove a stat boost by key
     */
    function removeStatBoostByKey(
        uint256 targetIndex,
        uint256 monIndex,
        StatBoostFlag boostFlag,
        uint160 key
    ) public {
        require(boostFlag != StatBoostFlag.Existence, "Cannot use Existence flag");

        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            loadEffectData(targetIndex, monIndex);

        uint256[] memory targetArray = (boostFlag == StatBoostFlag.Temp) ? tempBoosts : permBoosts;
        uint256[] memory newArray;
        bool found;
        uint8 oldStatType;

        (newArray, found, oldStatType) = removeBoost(targetArray, key);

        if (!found) {
            return; // Nothing to remove
        }

        // Update the appropriate array
        if (boostFlag == StatBoostFlag.Temp) {
            tempBoosts = newArray;
        } else {
            permBoosts = newArray;
        }

        // Recalculate the net delta for the affected stat
        int32 oldNetDelta = getNetDelta(netDeltas, oldStatType);
        int32 newTotalForStat = calculateTotalBoost(tempBoosts, oldStatType) + calculateTotalBoost(permBoosts, oldStatType);
        netDeltas = setNetDelta(netDeltas, oldStatType, newTotalForStat);

        // Calculate the diff and apply it
        int32 diff = newTotalForStat - oldNetDelta;
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(oldStatType), diff);
        ENGINE.setUpstreamCaller(address(0));

        // Save updated data
        saveEffectData(targetIndex, monIndex, netDeltas, tempBoosts, permBoosts);
    }

    /**
     * Remove all temporary boosts for a mon
     */
    function removeAllTemporaryBoosts(uint256 targetIndex, uint256 monIndex) public {
        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            loadEffectData(targetIndex, monIndex);

        if (tempBoosts.length == 0) {
            return; // Nothing to remove
        }

        // Calculate which stats need to be updated
        bool[5] memory statsToUpdate;
        for (uint256 i = 0; i < tempBoosts.length; i++) {
            (,, uint8 statType,) = unpackBoostInstance(tempBoosts[i]);
            statsToUpdate[statType] = true;
        }

        // Clear temp boosts
        tempBoosts = new uint256[](0);

        // Recalculate net deltas and apply changes
        ENGINE.setUpstreamCaller(msg.sender);
        for (uint8 statType = 0; statType < 5; statType++) {
            if (statsToUpdate[statType]) {
                int32 oldNetDelta = getNetDelta(netDeltas, statType);
                int32 newTotalForStat = calculateTotalBoost(permBoosts, statType);
                netDeltas = setNetDelta(netDeltas, statType, newTotalForStat);

                int32 diff = newTotalForStat - oldNetDelta;
                ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(statType), diff);
            }
        }
        ENGINE.setUpstreamCaller(address(0));

        // Save updated data
        saveEffectData(targetIndex, monIndex, netDeltas, tempBoosts, permBoosts);
    }

    // ============ EFFECT CALLBACKS ============

    function onApply(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        (uint160 key, uint8 statType, uint32 absBoostAmount, bool isPositive, uint256 boostFlagUint) =
            abi.decode(extraData, (uint160, uint8, uint32, bool, uint256));

        StatBoostFlag boostFlag = StatBoostFlag(boostFlagUint);

        // Load current effect data
        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            loadEffectData(targetIndex, monIndex);

        // Determine which array to modify
        uint256[] memory targetArray = (boostFlag == StatBoostFlag.Temp) ? tempBoosts : permBoosts;

        // Add or update the boost
        uint8 oldStatType;
        bool wasUpdate;
        (targetArray, oldStatType, wasUpdate) = addOrUpdateBoost(targetArray, key, absBoostAmount, statType, isPositive);

        // Update the appropriate array reference
        if (boostFlag == StatBoostFlag.Temp) {
            tempBoosts = targetArray;
        } else {
            permBoosts = targetArray;
        }

        // Recalculate net deltas for affected stats
        int32 oldNetDelta = getNetDelta(netDeltas, statType);
        int32 newTotalForStat = calculateTotalBoost(tempBoosts, statType) + calculateTotalBoost(permBoosts, statType);
        netDeltas = setNetDelta(netDeltas, statType, newTotalForStat);

        // Calculate diff and apply it
        int32 diff = newTotalForStat - oldNetDelta;
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(statType), diff);
        ENGINE.setUpstreamCaller(address(0));

        // If we updated a boost and it changed stats, we need to recalculate the old stat too
        if (wasUpdate && oldStatType != statType) {
            int32 oldStatOldNetDelta = getNetDelta(netDeltas, oldStatType);
            int32 oldStatNewTotal = calculateTotalBoost(tempBoosts, oldStatType) + calculateTotalBoost(permBoosts, oldStatType);
            netDeltas = setNetDelta(netDeltas, oldStatType, oldStatNewTotal);

            int32 oldStatDiff = oldStatNewTotal - oldStatOldNetDelta;
            ENGINE.setUpstreamCaller(msg.sender);
            ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(oldStatType), oldStatDiff);
            ENGINE.setUpstreamCaller(address(0));
        }

        // Save updated data
        saveEffectData(targetIndex, monIndex, netDeltas, tempBoosts, permBoosts);

        // Always remove the effect from the queue after running (we just update the stored data)
        return (extraData, true);
    }

    function onMonSwitchOut(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Remove all temporary boosts when switching out
        removeAllTemporaryBoosts(targetIndex, monIndex);

        return ("", false);
    }

    // ============ LEGACY COMPATIBILITY ============

    /**
     * Remove a stat boost (legacy interface)
     */
    function removeStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {
        uint160 key = generateKey(targetIndex, monIndex, msg.sender);
        removeStatBoostByKey(targetIndex, monIndex, boostFlag, key);
    }
}
