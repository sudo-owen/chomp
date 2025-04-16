// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Constants.sol";
import "../Enums.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {IEffect} from "../effects/IEffect.sol";

import {Ownable} from "../lib/Ownable.sol";
import {ITypeCalculator} from "../types/ITypeCalculator.sol";
import {AttackCalculator} from "./AttackCalculator.sol";
import {IMoveSet} from "./IMoveSet.sol";
import {ATTACK_PARAMS} from "./StandardAttackStructs.sol";

contract StandardAttack is IMoveSet, Ownable {

    IEngine immutable ENGINE;
    ITypeCalculator immutable TYPE_CALCULATOR;

    uint32 private _basePower;
    uint32 private _stamina;
    uint32 private _accuracy;
    uint32 private _priority;
    Type private _moveType;
    uint32 private _effectAccuracy;
    MoveClass private _moveClass;
    uint32 private _critRate;
    uint32 private _volatility;
    IEffect private _effect;

    string public name;

    constructor(address owner, IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR, ATTACK_PARAMS memory params) {
        ENGINE = _ENGINE;
        TYPE_CALCULATOR = _TYPE_CALCULATOR;
        _basePower = params.BASE_POWER;
        _stamina = params.STAMINA_COST;
        _accuracy = params.ACCURACY;
        _priority = params.PRIORITY;
        _moveType = params.MOVE_TYPE;
        _effectAccuracy = params.EFFECT_ACCURACY;
        _moveClass = params.MOVE_CLASS;
        _critRate = params.CRIT_RATE;
        _volatility = params.VOLATILITY;
        _effect = params.EFFECT;
        name = params.NAME;
        _initializeOwner(owner);
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256 rng) public virtual {
        if (basePower(battleKey) > 0) {
            AttackCalculator.calculateDamage(
                ENGINE,
                TYPE_CALCULATOR,
                battleKey,
                attackerPlayerIndex,
                basePower(battleKey),
                accuracy(battleKey),
                volatility(battleKey),
                moveType(battleKey),
                moveClass(battleKey),
                rng,
                critRate(battleKey)
            );
        }

        // Apply the effect as well if the accuracy is valid
        if (rng % 100 < _effectAccuracy) {
            uint256 defenderPlayerIndex = (attackerPlayerIndex + 1) % 2;
            uint256 defenderMonIndex =
                ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[defenderPlayerIndex];
            ENGINE.addEffect(defenderPlayerIndex, defenderMonIndex, _effect, "");
        }
    }

    function isValidTarget(bytes32, bytes calldata) public pure returns (bool) {
        return true;
    }

    function priority(bytes32, uint256) public view returns (uint32) {
        return _priority;
    }

    function stamina(bytes32, uint256, uint256) public view returns (uint32) {
        return _stamina;
    }

    function moveType(bytes32) public view returns (Type) {
        return _moveType;
    }

    function moveClass(bytes32) public view returns (MoveClass) {
        return _moveClass;
    }

    function critRate(bytes32) public view returns (uint32) {
        return _critRate;
    }

    function volatility(bytes32) public view returns (uint32) {
        return _volatility;
    }

    function basePower(bytes32) public view returns (uint32) {
        return _basePower;
    }

    function accuracy(bytes32) public view returns (uint32) {
        return _accuracy;
    }

    function effect(bytes32) public view returns (IEffect) {
        return _effect;
    }

    function effectAccuracy(bytes32) public view returns (uint32) {
        return _effectAccuracy;
    }

    function changeVar(uint256 varToChange, uint256 newValue) external onlyOwner {
        if (varToChange == 0) {
            _basePower = uint32(newValue);
        } else if (varToChange == 1) {
            _stamina = uint32(newValue);
        } else if (varToChange == 2) {
            _accuracy = uint32(newValue);
        } else if (varToChange == 3) {
            _priority = uint32(newValue);
        } else if (varToChange == 4) {
            _moveType = Type(newValue);
        } else if (varToChange == 5) {
            _effectAccuracy = uint32(newValue);
        } else if (varToChange == 6) {
            _moveClass = MoveClass(newValue);
        } else if (varToChange == 7) {
            _critRate = uint32(newValue);
        } else if (varToChange == 8) {
            _volatility = uint32(newValue);
        } else if (varToChange == 9) {
            _effect = IEffect(address(uint160(newValue)));
        }
    }
}
