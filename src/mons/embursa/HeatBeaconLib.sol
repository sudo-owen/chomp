// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";

library HeatBeaconLib {
    function _getKey(uint256 playerIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(playerIndex, "HEAT_BEACON"));
    }

    function _getPriorityBoost(IEngine engine, uint256 playerIndex) internal view returns (uint32) {
        bytes32 value = engine.getGlobalKV(engine.battleKeyForWrite(), _getKey(playerIndex));
        return value == bytes32("1") ? 1 : 0;
    }

    function _setPriorityBoost(IEngine engine, uint256 playerIndex) internal {
        engine.setGlobalKV(_getKey(playerIndex), bytes32("1"));
    }

    function _clearPriorityBoost(IEngine engine, uint256 playerIndex) internal {
        engine.setGlobalKV(_getKey(playerIndex), bytes32("0"));
    }
}
