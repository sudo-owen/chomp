// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Constants.sol";
import "../../src/Enums.sol";
import "../../src/Structs.sol";

import {IEngine} from "../../src/IEngine.sol";
import {IMoveSet} from "../../src/moves/IMoveSet.sol";

contract ForceSwitchMove is IMoveSet {
    struct Args {
        Type TYPE;
        uint32 STAMINA_COST;
        uint32 PRIORITY;
    }

    IEngine immutable ENGINE;
    Type immutable TYPE;
    uint32 immutable STAMINA_COST;
    uint32 immutable PRIORITY;

    constructor(IEngine _ENGINE, Args memory args) {
        ENGINE = _ENGINE;
        TYPE = args.TYPE;
        STAMINA_COST = args.STAMINA_COST;
        PRIORITY = args.PRIORITY;
    }

    function name() external pure returns (string memory) {
        return "Force Switch";
    }

    function move(bytes32, uint256, bytes memory extraData, uint256) external {
        // Decode data as (uint256 playerIndex, uint256 monToSwitchIndex)
        (uint256 playerIndex, uint256 monToSwitchIndex) = abi.decode(extraData, (uint256, uint256));

        // Use the new switchActiveMon function
        ENGINE.switchActiveMon(playerIndex, monToSwitchIndex);
    }

    function priority(bytes32) external view returns (uint32) {
        return PRIORITY;
    }

    function stamina(bytes32) external view returns (uint32) {
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
}
