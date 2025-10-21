// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Enums.sol";

interface ITypeCalculator {
    function getTypeEffectiveness(Type attackerType, Type defenderType, uint32 basePower) external view returns (uint32);
}
