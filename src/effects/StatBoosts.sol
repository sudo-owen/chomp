// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Enums.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {BasicEffect} from "./BasicEffect.sol";

/**
 Extra Data:
 [ uint32 empty | uint32 atkBoost | uint32 defBoost | uint32 spAtkBoost | uint32 spDefBoost | uint32 spdBoost ] <-- uint256
 [ [ uintX empty | uint128 key | uint32 boostAmount | uint8 boostInfo (uint4 empty | uint3 statType | uint1 direction)] ] <-- uint256 array for temporary boosts
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

    /**
     * Should only be applied once per mon per stat index
     *
     *     getKeyForMonIndex => hash(targetIndex, monIndex, statIndex, name(), TEMP/PERM/EXISTENCE)
     *     TEMP/PERM
     *     layout: [multiply factor | divide factor]:
     *     [120 bits: total multiplier, 8 bits: divisor]/[120 bits: total divider, 8 bits: divisor]
     *
     *     EXISTENCE
     *     layout: [1 bit: exists]
     */
    function name() public pure override returns (string memory) {
        return "Stat Boost";
    }

    function shouldRunAtStep(EffectStep r) external pure override returns (bool) {
        return (r == EffectStep.OnMonSwitchOut || r == EffectStep.OnApply);
    }

    function getKeyForMonIndexBoostExistence(uint256 targetIndex, uint256 monIndex, uint256 statIndex)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(targetIndex, monIndex, statIndex, name(), uint256(StatBoostFlag.Existence)));
    }

    function getKeyForMonIndexStat(uint256 targetIndex, uint256 monIndex, uint256 statIndex, StatBoostFlag boostFlag)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(targetIndex, monIndex, statIndex, name(), uint256(boostFlag)));
    }

    function calculateExistingBoost(uint256 targetIndex, uint256 monIndex, uint256 statIndex, bool tempOnly)
        public
        view
        returns (int32)
    {
        // First get the temporary boost
        bytes32 tempBoostKey = getKeyForMonIndexStat(targetIndex, monIndex, statIndex, StatBoostFlag.Temp);
        uint256 packedTempBoostValue = uint256(ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), tempBoostKey));

        // Get the base stat we are modifying
        uint256 baseStat = ENGINE.getMonValueForBattle(
            ENGINE.battleKeyForWrite(), targetIndex, monIndex, MonStateIndexName(statIndex)
        );
        uint256 originalBaseStat = baseStat;

        // Extract multiply and divide factors from the packed temporary boost value
        {
            uint128 packedTempMultiplyValue = uint128(packedTempBoostValue >> 128);
            uint128 packedTempDivideValue = uint128(packedTempBoostValue);

            uint256 numTempMultiplyBoosts = uint8(packedTempMultiplyValue);
            uint256 totalTempMultiplyBoost = packedTempMultiplyValue >> 8;

            uint256 numTempDivideBoosts = uint8(packedTempDivideValue);
            uint256 totalTempDivideBoost = packedTempDivideValue >> 8;

            // Apply temporary multiply boost
            if (numTempMultiplyBoosts > 0) {
                uint256 tempMultiplyDivisor = SCALE ** numTempMultiplyBoosts;
                baseStat = (baseStat * totalTempMultiplyBoost) / tempMultiplyDivisor;
            }

            // Apply temporary divide boost
            if (numTempDivideBoosts > 0) {
                uint256 tempDivideDivisor = SCALE ** numTempDivideBoosts;
                baseStat = (baseStat * totalTempDivideBoost) / tempDivideDivisor;
            }
        }
        if (tempOnly) {
            return int32(int256(baseStat)) - int32(int256(originalBaseStat));
        }
        // Then apply the permanent boosts if we are not only calculating the temporary boost
        {
            bytes32 permBoostKey = getKeyForMonIndexStat(targetIndex, monIndex, statIndex, StatBoostFlag.Perm);
            uint256 packedPermBoostValue = uint256(ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), permBoostKey));

            // Extract multiply and divide factors from the packed perm boost value
            uint128 packedPermMultiplyValue = uint128(packedPermBoostValue >> 128);
            uint128 packedPermDivideValue = uint128(packedPermBoostValue);

            uint256 numPermMultiplyBoosts = uint8(packedPermMultiplyValue);
            uint256 totalPermMultiplyBoost = packedPermMultiplyValue >> 8;

            uint256 numPermDivideBoosts = uint8(packedPermDivideValue);
            uint256 totalPermDivideBoost = packedPermDivideValue >> 8;

            // Apply permanent multiply boost
            if (numPermMultiplyBoosts > 0) {
                uint256 permMultiplyDivisor = SCALE ** numPermMultiplyBoosts;
                baseStat = (baseStat * totalPermMultiplyBoost) / permMultiplyDivisor;
            }

            // Apply permanent divide boost
            if (numPermDivideBoosts > 0) {
                uint256 permDivideDivisor = SCALE ** numPermDivideBoosts;
                baseStat = (baseStat * totalPermDivideBoost) / permDivideDivisor;
            }
        }

        return int32(int256(baseStat)) - int32(int256(originalBaseStat));
    }

    function _updateStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) internal {
        // Get the existing boost amount
        int32 existingBoostAmount = calculateExistingBoost(targetIndex, monIndex, statIndex, false);

        bytes32 statKey = getKeyForMonIndexStat(targetIndex, monIndex, statIndex, StatBoostFlag(boostFlag));
        uint256 multiplyAndDivideTotal = uint256(ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), statKey));

        // The packed boost value is either the first or last 128 bits, depending on if we are multiplying or dividing
        uint128 packedBoostValue = uint128(multiplyAndDivideTotal);
        if (boostType == StatBoostType.Multiply) {
            packedBoostValue = uint128(multiplyAndDivideTotal >> 128);
        }

        // Decode the packed boost value
        uint256 numBoosts = uint8(packedBoostValue);
        uint256 totalBoost = packedBoostValue >> 8;

        // Update the boost amount (either we are adding a boost, or we are removing a boost)
        // We only ever pass in negative values to the boost amount if we want to remove an existing value
        // NOT to signify a divide boost, use the flag for that
        if (numBoosts == 0) {
            totalBoost = uint256(uint32(boostAmount));
            numBoosts = 1;
        } else if (boostAmount > 0) {
            totalBoost = totalBoost * uint32(boostAmount);
            numBoosts = numBoosts + 1;
        } else {
            totalBoost = totalBoost / uint32(boostAmount * -1);
            numBoosts = numBoosts - 1;
        }

        // Repack the boost value
        uint256 newPackedBoostValue = (totalBoost << 8) | numBoosts;

        // Set the new multiply and divide total by clearing out the old bits
        if (boostType == StatBoostType.Multiply) {
            uint256 bottomBits = multiplyAndDivideTotal & uint256(type(uint128).max);
            // Combine with the new packed value in the top 128 bits
            multiplyAndDivideTotal = (newPackedBoostValue << 128) | bottomBits;
        } else {
            // Clear the bottom 128 bits by masking with the top 128 bits
            uint256 topBits = (multiplyAndDivideTotal & (uint256(type(uint128).max) << 128));
            // Combine with the new packed value in the bottom 128 bits
            multiplyAndDivideTotal = topBits | newPackedBoostValue;
        }
        ENGINE.setGlobalKV(statKey, bytes32(multiplyAndDivideTotal));

        // Set the new boost amount
        int32 newBoostAmount = calculateExistingBoost(targetIndex, monIndex, statIndex, false);
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName(statIndex), newBoostAmount - existingBoostAmount);
        ENGINE.setUpstreamCaller(address(0));
    }

    // boostAmount is in percent, specify if it should scale up or down by that % amount
    function addStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {
        if (boostType == StatBoostType.Divide) {
            boostAmount = -1 * boostAmount;
        }
        int32 actualBoost = int32(int256(SCALE)) + boostAmount;
        bytes memory extraData = abi.encode(statIndex, actualBoost, uint256(boostType), uint256(boostFlag));
        ENGINE.setUpstreamCaller(msg.sender);
        ENGINE.addEffect(targetIndex, monIndex, this, extraData);
        ENGINE.setUpstreamCaller(address(0));
    }

    function removeStatBoost(
        uint256 targetIndex,
        uint256 monIndex,
        uint256 statIndex,
        int32 boostAmount,
        StatBoostType boostType,
        StatBoostFlag boostFlag
    ) public {
        _updateStatBoost(targetIndex, monIndex, statIndex, (-1 * boostAmount), boostType, boostFlag);
    }

    function onApply(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        // Check if an existing stat boost for the mon / stat index already exists
        (uint256 statIndex, int32 boostAmount, uint256 boostType, uint256 boostFlag) =
            abi.decode(extraData, (uint256, int32, uint256, uint256));
        bool removeAfterRun = false;

        // Check if we've already applied a stat boost for the mon
        bytes32 existenceKey = getKeyForMonIndexBoostExistence(targetIndex, monIndex, statIndex);
        if (ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), existenceKey) == bytes32(0)) {
            ENGINE.setGlobalKV(existenceKey, bytes32("1"));
        } else {
            removeAfterRun = true;
        }

        // Set the new boost amount
        _updateStatBoost(
            targetIndex, monIndex, statIndex, boostAmount, StatBoostType(boostType), StatBoostFlag(boostFlag)
        );

        return (extraData, removeAfterRun);
    }

    function clearTempBoost(uint256 targetIndex, uint256 monIndex, uint256 statIndex) public returns (bool) {
        bytes32 statKey = getKeyForMonIndexBoostExistence(targetIndex, monIndex, uint256(statIndex));
        if (ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), statKey) != bytes32(0)) {
            // Get the existing temporary boost amount
            int32 existingBoostAmount = calculateExistingBoost(targetIndex, monIndex, uint256(statIndex), true);
            if (existingBoostAmount != 0) {
                // Set upstream caller
                ENGINE.setUpstreamCaller(msg.sender);
                // Clear the temporary boost in both directions
                bytes32 tempBoostKey =
                    getKeyForMonIndexStat(targetIndex, monIndex, uint256(statIndex), StatBoostFlag.Temp);
                ENGINE.setGlobalKV(tempBoostKey, bytes32(0));
                // Reset the temporary boost
                ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName(statIndex), existingBoostAmount * -1);
                ENGINE.setUpstreamCaller(address(0));
                return true;
            }
        }
        return false;
    }

    function onMonSwitchOut(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Check for ATK/DEF/SpATK/SpDEF/SPD boosts
        uint256[] memory statIndexNames = new uint256[](5);
        statIndexNames[0] = uint256(MonStateIndexName.Attack);
        statIndexNames[1] = uint256(MonStateIndexName.Defense);
        statIndexNames[2] = uint256(MonStateIndexName.SpecialAttack);
        statIndexNames[3] = uint256(MonStateIndexName.SpecialDefense);
        statIndexNames[4] = uint256(MonStateIndexName.Speed);
        for (uint256 i = 0; i < statIndexNames.length; i++) {
            clearTempBoost(targetIndex, monIndex, statIndexNames[i]);
        }
        return ("", false);
    }
}
