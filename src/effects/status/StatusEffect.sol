// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../../IEngine.sol";
import {BasicEffect} from "../BasicEffect.sol";
import {StatusEffectLib} from "./StatusEffectLib.sol";

abstract contract StatusEffect is BasicEffect {
    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    // Whether or not to add the effect if the step condition is met
    // NOTE: somewhat weirdly, this is a state mutating function
    function shouldApply(bytes memory, uint256 targetIndex, uint256 monIndex) public virtual override returns (bool) {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        bytes32 keyForMon = StatusEffectLib.getKeyForMonIndex(targetIndex, monIndex);

        // Get value from ENGINE KV
        bytes32 monStatusFlag = ENGINE.getGlobalKV(battleKey, keyForMon);

        // Check if a status already exists for the mon
        if (monStatusFlag == bytes32(0)) {
            // If not, set the value to be the address of the status and return true
            ENGINE.setGlobalKV(keyForMon, bytes32(uint256(uint160(address(this)))));
            return true;
        } else {
            // Otherwise return false
            return false;
        }
    }

    function onRemove(bytes memory, uint256 targetIndex, uint256 monIndex) public virtual override {
        // On remove, reset the status flag
        ENGINE.setGlobalKV(StatusEffectLib.getKeyForMonIndex(targetIndex, monIndex), bytes32(0));
    }
}
