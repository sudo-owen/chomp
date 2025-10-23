// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../../src/IEngine.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";
import {MoveClass, Type, ExtraDataType} from "../../src/Enums.sol";

contract TestMove is IMoveSet {

    MoveClass private _moveClass;
    Type private _moveType;
    uint32 private _staminaCost;

    constructor(MoveClass moveClassToUse, Type moveTypeToUse, uint32 staminaCost) {
        _moveClass = moveClassToUse;
        _moveType = moveTypeToUse;
        _staminaCost = staminaCost;
    }

    function name() external pure returns (string memory) {
        return "Test Move";
    }

    function move(bytes32, uint256, bytes memory, uint256) external pure {
        // No-op
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return 1;
    }

    function stamina(bytes32, uint256, uint256) external view returns (uint32) {
        return _staminaCost;
    }

    function moveType(bytes32) external pure returns (Type) {
        return Type.Fire;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function moveClass(bytes32) external pure returns (MoveClass) {
        return MoveClass.Physical;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}

contract TestMoveFactory {

    constructor() {}

    function createMove(MoveClass moveClassToUse, Type moveTypeToUse, uint32 staminaCost) external returns (IMoveSet) {
        return new TestMove(moveClassToUse, moveTypeToUse, staminaCost);
    }
}
