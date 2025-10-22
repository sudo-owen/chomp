// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../../src/Enums.sol";
import {ITypeCalculator} from "../../src/types/ITypeCalculator.sol";

contract TestTypeCalculator is ITypeCalculator {

    uint256 constant private ZERO_VALUE = type(uint).max - 1;

    mapping(uint attacker => mapping(uint defender => uint multiplier)) private typeOverride;

    function setTypeEffectiveness(Type attacker, Type defender, uint256 value) public {
        if (value == 0) {
            typeOverride[uint(attacker)][uint(defender)] = ZERO_VALUE;
        }
        else {
            typeOverride[uint(attacker)][uint(defender)] = value;
        }
    }

    function getTypeEffectiveness(Type attacker, Type defender, uint32 basePower) external view returns (uint32) {
        uint256 effectiveness = typeOverride[uint(attacker)][uint(defender)];
        if (effectiveness != 0) {
            if (effectiveness == ZERO_VALUE) {
                return 0;
            }
            else if (effectiveness == 5) {
                return basePower / 2;
            }
            else {
                return basePower * 2;
            }
        }
        return basePower;
    }
}
