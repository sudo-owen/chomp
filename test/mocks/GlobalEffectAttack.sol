// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Enums.sol";
import "../../src/Structs.sol";

import {IEngine} from "../../src/IEngine.sol";
import {IEffect} from "../../src/effects/IEffect.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";

contract GlobalEffectAttack is IMoveSet {
    struct Args {
        Type TYPE;
        uint32 STAMINA_COST;
        uint32 PRIORITY;
    }

    IEngine immutable ENGINE;
    IEffect immutable EFFECT;
    Type immutable TYPE;
    uint32 immutable STAMINA_COST;
    uint32 immutable PRIORITY;

    constructor(IEngine _ENGINE, IEffect _EFFECT, Args memory args) {
        ENGINE = _ENGINE;
        EFFECT = _EFFECT;
        TYPE = args.TYPE;
        STAMINA_COST = args.STAMINA_COST;
        PRIORITY = args.PRIORITY;
    }

    function name() external pure returns (string memory) {
        return "Effect Attack";
    }

    function move(bytes32, uint256, bytes memory extraData, uint256) external {
        ENGINE.addEffect(2, 0, EFFECT, extraData);
    }

    function priority(bytes32, uint256) external view returns (uint32) {
        return PRIORITY;
    }

    function stamina(bytes32, uint256, uint256) external view returns (uint32) {
        return STAMINA_COST;
    }

    function moveType(bytes32) external view returns (Type) {
        return TYPE;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function moveClass(bytes32) external pure returns (MoveClass) {
        return MoveClass.Physical;
    }

    function basePower(bytes32) external pure returns (uint32) {
        return 0;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}
