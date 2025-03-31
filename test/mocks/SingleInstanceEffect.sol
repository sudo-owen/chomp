// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Enums.sol";
import "../../src/Structs.sol";

import {IEngine} from "../../src/IEngine.sol";
import {BasicEffect} from "../../src/effects/BasicEffect.sol";

contract SingleInstanceEffect is BasicEffect {
    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() external override pure returns (string memory) {
        return "Instant Death";
    }

    function shouldRunAtStep(EffectStep r) external override pure returns (bool) {
        return r == EffectStep.OnApply;
    }

    function onApply(uint256, bytes memory, uint256 targetIndex, uint256 monIndex) external override returns (bytes memory, bool removeAfterRun) {
        bytes32 indexHash = keccak256(abi.encode(targetIndex, monIndex));
        ENGINE.setGlobalKV(indexHash, bytes32("true"));
        return ("", false);
    }

    function shouldApply(bytes memory, uint256 targetIndex, uint256 monIndex) external override view returns (bool) {
        bytes32 indexHash = keccak256(abi.encode(targetIndex, monIndex));
        bytes32 value = ENGINE.getGlobalKV(ENGINE.battleKeyForWrite(), indexHash);
        return value == bytes32(0);
    }
}
