// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {AttackCalculator} from "../../moves/AttackCalculator.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";
import {HeatBeaconLib} from "./HeatBeaconLib.sol";

contract Q5 is IMoveSet, BasicEffect {
    uint256 public constant DELAY = 5;
    uint32 public constant BASE_POWER = 150;

    IEngine immutable ENGINE;
    ITypeCalculator immutable TYPE_CALCULATOR;

    constructor(IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR) {
        ENGINE = _ENGINE;
        TYPE_CALCULATOR = _TYPE_CALCULATOR;
    }

    function name() public pure override(IMoveSet, BasicEffect) returns (string memory) {
        return "Q5";
    }

    function move(bytes32, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        // Add effect to global effects
        ENGINE.addEffect(2, 2, this, abi.encode(1, attackerPlayerIndex));

        // Clear the priority boost
        if (HeatBeaconLib._getPriorityBoost(ENGINE, attackerPlayerIndex) == 1) {
            HeatBeaconLib._clearPriorityBoost(ENGINE, attackerPlayerIndex);
        }
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 5;
    }

    function priority(bytes32, uint256 attackerPlayerIndex) external view returns (uint32) {
        return DEFAULT_PRIORITY + HeatBeaconLib._getPriorityBoost(ENGINE, attackerPlayerIndex);
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Fire;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Special;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }

    /**
     *  Effect implementation
     */
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.RoundStart);
    }

    function onRoundStart(uint256 rng, bytes memory extraData, uint256, uint256)
        external
        override
        returns (bytes memory, bool)
    {
        (uint256 turnCount, uint256 attackerPlayerIndex) = abi.decode(extraData, (uint256, uint256));
        if (turnCount == DELAY) {
            // Deal damage
            AttackCalculator._calculateDamage(
                ENGINE,
                TYPE_CALCULATOR,
                ENGINE.battleKeyForWrite(),
                attackerPlayerIndex,
                BASE_POWER,
                DEFAULT_ACCRUACY,
                DEFAULT_VOL,
                moveType(ENGINE.battleKeyForWrite()),
                moveClass(ENGINE.battleKeyForWrite()),
                rng,
                DEFAULT_CRIT_RATE
            );
            return (extraData, true);
        } else {
            return (abi.encode((turnCount + 1), attackerPlayerIndex), false);
        }
    }
}
