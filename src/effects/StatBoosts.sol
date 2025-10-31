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
    uint256 public constant SCALE = 100;

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
     * boostAmount: percentage in SCALE units (e.g., 10 = 10% = multiply by 110/100 or 90/100)
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
     * Find the StatBoosts effect for a mon and return its index and extraData
     * Returns: (found, effectIndex, extraData)
     */
    function findStatBoostsEffect(uint256 targetIndex, uint256 monIndex)
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

    /**
     * Decode extraData into its components
     */
    function decodeExtraData(bytes memory extraData)
        internal
        pure
        returns (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts)
    {
        if (extraData.length == 0) {
            tempBoosts = new uint256[](0);
            permBoosts = new uint256[](0);
            netDeltas = 0;
        } else {
            (netDeltas, tempBoosts, permBoosts) = abi.decode(extraData, (uint256, uint256[], uint256[]));
        }
    }

    /**
     * Encode data into extraData
     */
    function encodeExtraData(uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(netDeltas, tempBoosts, permBoosts);
    }

    // ============ BOOST MANIPULATION ============

    /**
     * Calculate the total multiplicative boost for a specific stat from an array of boost instances
     * Returns the delta to apply to the base stat
     *
     * For example, if baseStat=100 and we have boosts of +10% and +5%:
     * - Multiply by (100+10)/100 * (100+5)/100 = 1.10 * 1.05 = 1.155
     * - newStat = 100 * 1.155 = 115.5 ≈ 115
     * - delta = 115 - 100 = 15
     */
    function calculateStatDelta(
        uint256[] memory tempBoosts,
        uint256[] memory permBoosts,
        uint8 statType,
        uint32 baseStat
    ) internal pure returns (int32 delta) {
        // Start with base stat
        uint256 totalMultiplier = SCALE;
        uint256 totalDivisor = 1;

        // Collect all boosts for this stat
        uint256 numMultiply = 0;
        uint256 numDivide = 0;

        // Process temp boosts
        for (uint256 i = 0; i < tempBoosts.length; i++) {
            (, uint32 boostAmount, uint8 boostStatType, bool isPositive) = unpackBoostInstance(tempBoosts[i]);
            if (boostStatType == statType) {
                if (isPositive) {
                    totalMultiplier = totalMultiplier * (SCALE + boostAmount);
                    numMultiply++;
                } else {
                    totalMultiplier = totalMultiplier * (SCALE - boostAmount);
                    numMultiply++;
                }
            }
        }

        // Process perm boosts
        for (uint256 i = 0; i < permBoosts.length; i++) {
            (, uint32 boostAmount, uint8 boostStatType, bool isPositive) = unpackBoostInstance(permBoosts[i]);
            if (boostStatType == statType) {
                if (isPositive) {
                    totalMultiplier = totalMultiplier * (SCALE + boostAmount);
                    numMultiply++;
                } else {
                    totalMultiplier = totalMultiplier * (SCALE - boostAmount);
                    numMultiply++;
                }
            }
        }

        // Calculate divisor (SCALE raised to the power of total number of boosts + 1 for the initial SCALE)
        totalDivisor = SCALE ** (numMultiply + 1);

        // Apply the multiplier
        uint256 newStat = (uint256(baseStat) * totalMultiplier) / totalDivisor;

        // Return the delta
        return int32(uint32(newStat)) - int32(uint32(baseStat));
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

        // Convert boostType to direction
        bool isPositive = (boostType == StatBoostType.Multiply);
        uint32 absBoostAmount = uint32(boostAmount > 0 ? boostAmount : -boostAmount);
        uint8 statType = monStateIndexToStatType(statIndex);

        // Get current effect data (if exists)
        (bool found, uint256 effectIndex, bytes memory currentExtraData) = findStatBoostsEffect(targetIndex, monIndex);
        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            decodeExtraData(currentExtraData);

        // Get the base stat value
        uint32 baseStat = ENGINE.getMonValueForBattle(
            ENGINE.battleKeyForWrite(),
            targetIndex,
            monIndex,
            statTypeToMonStateIndex(statType)
        );

        // Calculate old delta
        int32 oldDelta = getNetDelta(netDeltas, statType);

        // Add or update the boost
        uint8 oldStatType;
        bool wasUpdate;
        if (boostFlag == StatBoostFlag.Temp) {
            (tempBoosts, oldStatType, wasUpdate) = addOrUpdateBoost(tempBoosts, key, absBoostAmount, statType, isPositive);
        } else {
            (permBoosts, oldStatType, wasUpdate) = addOrUpdateBoost(permBoosts, key, absBoostAmount, statType, isPositive);
        }

        // Calculate new delta for the affected stat
        int32 newDelta = calculateStatDelta(tempBoosts, permBoosts, statType, baseStat);
        netDeltas = setNetDelta(netDeltas, statType, newDelta);

        // Apply the difference
        int32 diff = newDelta - oldDelta;
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(statType), diff);

        // If we updated a boost and it changed stats, recalculate the old stat too
        if (wasUpdate && oldStatType != statType) {
            uint32 oldStatBaseStat = ENGINE.getMonValueForBattle(
                ENGINE.battleKeyForWrite(),
                targetIndex,
                monIndex,
                statTypeToMonStateIndex(oldStatType)
            );
            int32 oldStatOldDelta = getNetDelta(netDeltas, oldStatType);
            int32 oldStatNewDelta = calculateStatDelta(tempBoosts, permBoosts, oldStatType, oldStatBaseStat);
            netDeltas = setNetDelta(netDeltas, oldStatType, oldStatNewDelta);

            int32 oldStatDiff = oldStatNewDelta - oldStatOldDelta;
            ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(oldStatType), oldStatDiff);
        }

        ENGINE.setUpstreamCaller(address(0));

        // Update or add the effect
        if (found) {
            ENGINE.removeEffect(targetIndex, monIndex, effectIndex);
        }
        ENGINE.addEffect(targetIndex, monIndex, this, encodeExtraData(netDeltas, tempBoosts, permBoosts));
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

        // Get current effect data
        (bool found, uint256 effectIndex, bytes memory currentExtraData) = findStatBoostsEffect(targetIndex, monIndex);
        if (!found) {
            return; // No effect to remove from
        }

        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            decodeExtraData(currentExtraData);

        // Remove the boost
        uint256[] memory newArray;
        bool boostFound;
        uint8 oldStatType;

        if (boostFlag == StatBoostFlag.Temp) {
            (newArray, boostFound, oldStatType) = removeBoost(tempBoosts, key);
            tempBoosts = newArray;
        } else {
            (newArray, boostFound, oldStatType) = removeBoost(permBoosts, key);
            permBoosts = newArray;
        }

        if (!boostFound) {
            return; // Nothing to remove
        }

        // Get the base stat value
        uint32 baseStat = ENGINE.getMonValueForBattle(
            ENGINE.battleKeyForWrite(),
            targetIndex,
            monIndex,
            statTypeToMonStateIndex(oldStatType)
        );

        // Recalculate delta for the affected stat
        int32 oldDelta = getNetDelta(netDeltas, oldStatType);
        int32 newDelta = calculateStatDelta(tempBoosts, permBoosts, oldStatType, baseStat);
        netDeltas = setNetDelta(netDeltas, oldStatType, newDelta);

        // Apply the difference
        int32 diff = newDelta - oldDelta;
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(oldStatType), diff);
        ENGINE.setUpstreamCaller(address(0));

        // Update the effect
        ENGINE.removeEffect(targetIndex, monIndex, effectIndex);
        if (tempBoosts.length > 0 || permBoosts.length > 0) {
            // Still have boosts, keep the effect
            ENGINE.addEffect(targetIndex, monIndex, this, encodeExtraData(netDeltas, tempBoosts, permBoosts));
        }
    }

    /**
     * Remove all temporary boosts for a mon
     */
    function removeAllTemporaryBoosts(uint256 targetIndex, uint256 monIndex) public {
        // Get current effect data
        (bool found, uint256 effectIndex, bytes memory currentExtraData) = findStatBoostsEffect(targetIndex, monIndex);
        if (!found) {
            return; // No effect to modify
        }

        (uint256 netDeltas, uint256[] memory tempBoosts, uint256[] memory permBoosts) =
            decodeExtraData(currentExtraData);

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

        // Recalculate and apply changes for each affected stat
        ENGINE.setUpstreamCaller(msg.sender);
        for (uint8 statType = 0; statType < 5; statType++) {
            if (statsToUpdate[statType]) {
                uint32 baseStat = ENGINE.getMonValueForBattle(
                    ENGINE.battleKeyForWrite(),
                    targetIndex,
                    monIndex,
                    statTypeToMonStateIndex(statType)
                );

                int32 oldDelta = getNetDelta(netDeltas, statType);
                int32 newDelta = calculateStatDelta(tempBoosts, permBoosts, statType, baseStat);
                netDeltas = setNetDelta(netDeltas, statType, newDelta);

                int32 diff = newDelta - oldDelta;
                ENGINE.updateMonState(targetIndex, monIndex, statTypeToMonStateIndex(statType), diff);
            }
        }
        ENGINE.setUpstreamCaller(address(0));

        // Update the effect
        ENGINE.removeEffect(targetIndex, monIndex, effectIndex);
        if (permBoosts.length > 0) {
            // Still have permanent boosts, keep the effect
            ENGINE.addEffect(targetIndex, monIndex, this, encodeExtraData(netDeltas, tempBoosts, permBoosts));
        }
    }

    // ============ EFFECT CALLBACKS ============

    function onApply(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        // This is called when the effect is added/updated
        // We've already done all the work in the public functions
        // Just keep the effect with its data
        return (extraData, false);
    }

    function onMonSwitchOut(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Remove all temporary boosts when switching out
        removeAllTemporaryBoosts(targetIndex, monIndex);

        // Return the updated extra data (though it will be handled by removeAllTemporaryBoosts)
        return (extraData, false);
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
