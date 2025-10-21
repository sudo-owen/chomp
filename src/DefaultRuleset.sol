// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Structs.sol";
import "./moves/IMoveSet.sol";

import {IEngine} from "./IEngine.sol";
import {IRuleset} from "./IRuleset.sol";

import {IEffect} from "./effects/IEffect.sol";

contract DefaultRuleset is IRuleset {
    IEngine immutable ENGINE;

    IEffect[] public effects;

    constructor(IEngine _ENGINE, IEffect[] memory _effects) {
        ENGINE = _ENGINE;
        for (uint256 i; i < _effects.length; i++) {
            effects.push(_effects[i]);
        }
    }

    function getInitialGlobalEffects() external view returns (IEffect[] memory, bytes[] memory) {
        bytes[] memory data = new bytes[](1);
        return (effects, data);
    }
}
