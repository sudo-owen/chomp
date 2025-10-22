// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../src/Enums.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

/**
 * Mock TypeCalculator with mutable type effectiveness mapping for testing.
 * Allows tests to set custom type matchups as needed.
 * Default effectiveness is 1x (neutral) for all matchups.
 */
contract MockTypeCalculator is ITypeCalculator {
    // Maps (attackerType, defenderType) -> effectiveness multiplier
    // 0 = immune (0x), 1 = not very effective (0.5x), 2 = neutral (1x), 3 = super effective (2x)
    mapping(Type => mapping(Type => uint8)) public effectiveness;

    constructor() {
        // All matchups default to neutral (2 = 1x)
    }

    function setEffectiveness(Type attackerType, Type defenderType, uint8 multiplier) external {
        effectiveness[attackerType][defenderType] = multiplier;
    }

    function getTypeEffectiveness(Type attackerType, Type defenderType, uint32 basePower)
        external
        view
        returns (uint32)
    {
        uint8 multiplier = effectiveness[attackerType][defenderType];

        if (multiplier == 0) {
            return 0; // Immune
        } else if (multiplier == 1) {
            return basePower / 2; // Not very effective
        } else if (multiplier == 3) {
            return basePower * 2; // Super effective
        } else {
            return basePower; // Neutral (default)
        }
    }
}
