// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../src/Enums.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

/**
 * Mock TypeCalculator that provides predictable type advantages for testing:
 * - Fire is super effective (2x) against Nature
 * - Nature is not very effective (0.5x) against Fire
 * - All other combinations return base power (1x)
 */
contract MockTypeCalculator is ITypeCalculator {
    function getTypeEffectiveness(Type attackerType, Type defenderType, uint32 basePower)
        external
        pure
        returns (uint32)
    {
        // Fire attacking Nature = 2x effectiveness (super effective)
        if (attackerType == Type.Fire && defenderType == Type.Nature) {
            return basePower * 2;
        }

        // Nature attacking Fire = 0.5x effectiveness (not very effective)
        if (attackerType == Type.Nature && defenderType == Type.Fire) {
            return basePower / 2;
        }

        // All other combinations are neutral (1x)
        return basePower;
    }
}
