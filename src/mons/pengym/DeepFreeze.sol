// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {AttackCalculator} from "../../moves/AttackCalculator.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract DeepFreeze is IMoveSet {

    uint32 constant public BASE_POWER = 90;

    IEngine immutable ENGINE;
    IEffect immutable FROSTBITE;
    ITypeCalculator immutable TYPE_CALCULATOR;

    constructor(IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR, IEffect _FROSTBITE) {
        ENGINE = _ENGINE;
        FROSTBITE = _FROSTBITE;
        TYPE_CALCULATOR = _TYPE_CALCULATOR;
    }

    function name() public pure override returns (string memory) {
        return "Deep Freeze";
    }

    function _frostbiteExists(bytes32 battleKey, uint256 targetIndex, uint256 monIndex) internal view returns (uint256, bool) {
        (IEffect[] memory effects, ) = ENGINE.getEffects(battleKey, targetIndex, monIndex);
        uint256 numEffects = effects.length;
        for (uint i; i < numEffects;) {
            if (address(effects[i]) == address(FROSTBITE)) {
                return (i, true);
            }
            unchecked {
                 ++i;
            }
        }
        return (0, false);
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256 rng) external {
        uint256 otherPlayerIndex = (attackerPlayerIndex + 1) % 2;
        uint256 otherPlayerActiveMonIndex =
            ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[otherPlayerIndex];
        uint32 damageToDeal = BASE_POWER;
        (uint256 frostbiteIndex, bool hasFrostbite) = _frostbiteExists(battleKey, otherPlayerIndex, otherPlayerActiveMonIndex);
        // Remove frostbite if it exists, and double the damage dealt
        if (hasFrostbite) {
            ENGINE.removeEffect(otherPlayerIndex, otherPlayerActiveMonIndex, frostbiteIndex);
            damageToDeal = damageToDeal * 2;
        }
        // Deal damage
        AttackCalculator.calculateDamage(
            ENGINE,
            TYPE_CALCULATOR,
            battleKey,
            attackerPlayerIndex,
            damageToDeal,
            DEFAULT_ACCRUACY,
            DEFAULT_VOL,
            moveType(battleKey),
            moveClass(battleKey),
            rng,
            DEFAULT_CRIT_RATE
        );
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 3;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Ice;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Physical;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

}
