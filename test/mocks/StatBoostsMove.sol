// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Enums.sol";
import "../../src/Structs.sol";

import {IEngine} from "../../src/IEngine.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";

import {StatBoosts} from "../../src/effects/StatBoosts.sol";

contract StatBoostsMove is IMoveSet {
    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        STAT_BOOSTS = _STAT_BOOSTS;
    }

    function name() external pure returns (string memory) {
        return "";
    }

    function move(bytes32, uint256, bytes memory extraData, uint256) external {
        (uint256 playerIndex, uint256 monIndex, uint256 statIndex, int32 boostAmount) =
            abi.decode(extraData, (uint256, uint256, uint256, int32));

        // For all tests, we'll use Temp stat boosts with Multiply type for positive boosts
        // and Divide type for negative boosts
        StatBoostType boostType = boostAmount > 0 ? StatBoostType.Multiply : StatBoostType.Divide;

        // Convert negative boosts to positive for the divide operation
        if (boostAmount < 0) {
            boostAmount = -boostAmount;
        }

        STAT_BOOSTS.addStatBoost(playerIndex, monIndex, statIndex, boostAmount, boostType, StatBoostFlag.Temp);
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return 0;
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 0;
    }

    function moveType(bytes32) external pure returns (Type) {
        return Type.Air;
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
