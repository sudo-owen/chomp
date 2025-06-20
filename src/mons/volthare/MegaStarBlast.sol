// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {AttackCalculator} from "../../moves/AttackCalculator.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract MegaStarBlast is IMoveSet {

    uint32 constant public DEFAULT_ACCURACY = 50;
    uint32 constant public ZAP_ACCURACY = 30;
    uint32 constant public BASE_POWER = 150;

    IEngine immutable ENGINE;
    ITypeCalculator immutable TYPE_CALCULATOR;
    IEffect immutable ZAP_STATUS;
    IEffect immutable STORM;

    constructor(IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR, IEffect _ZAP_STATUS, IEffect _STORM) {
        ENGINE = _ENGINE;
        TYPE_CALCULATOR = _TYPE_CALCULATOR;
        ZAP_STATUS = _ZAP_STATUS;
        STORM = _STORM;
    }

    function name() public pure override returns (string memory) {
        return "Mega Star Blast";
    }

    function _checkForOverclock(bytes32 battleKey) internal view returns (int32) {
        // Check all global effects to see if Storm is active
        (IEffect[] memory effects, ) = ENGINE.getEffects(battleKey, 2, 2);
        for (uint256 i; i < effects.length; i++) {
            if (address(effects[i]) == address(STORM)) {
                return int32(int256(i));
            }
        }
        return -1;
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256 rng) external {
        // Check if Storm is active
        uint32 acc = DEFAULT_ACCURACY;
        int32 stormIndex = _checkForOverclock(battleKey);
        if (stormIndex >= 0) {
            // Remove Storm
            ENGINE.removeEffect(2, 2, uint256(uint32(stormIndex)));
            // Upgrade accuracy
            acc = 100;
        }
        // Deal damage
        AttackCalculator._calculateDamage(
            ENGINE,
            TYPE_CALCULATOR,
            battleKey,
            attackerPlayerIndex,
            BASE_POWER,
            acc,
            DEFAULT_VOL,
            moveType(battleKey),
            moveClass(battleKey),
            rng,
            DEFAULT_CRIT_RATE
        );
        // Apply Zap if rng allows
        uint256 rng2 = uint256(keccak256(abi.encode(rng)));
        if (rng2 % 100 < ZAP_ACCURACY) {
            uint256 defenderPlayerIndex = (attackerPlayerIndex + 1) % 2;
            uint256 defenderMonIndex =
                ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[defenderPlayerIndex];
            ENGINE.addEffect(defenderPlayerIndex, defenderMonIndex, ZAP_STATUS, "");
        }
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 3;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY + 2;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Lightning;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Special;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

}
