// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {ExtraDataType, MoveClass, Type} from "../../src/Enums.sol";
import {IEngine} from "../../src/IEngine.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";

contract EditEffectAttack is IMoveSet {

    IEngine immutable ENGINE;
    
    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() external pure returns (string memory) {
        return "Edit Effect Attack";
    }

    function move(bytes32, uint256, bytes memory extraData, uint256) external {
        (uint256 targetIndex, uint256 monIndex, uint256 effectIndex) = abi.decode(extraData, (uint256, uint256, uint256));
        ENGINE.editEffect(targetIndex, monIndex, effectIndex, abi.encode(69));
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return 1;
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 0;
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

    function basePower(bytes32) external pure returns (uint32) {
        return 0;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }   
}
