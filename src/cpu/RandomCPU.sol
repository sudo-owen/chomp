// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICPU} from "./ICPU.sol";
import {IEngine} from "../IEngine.sol";
import {IValidator} from "../IValidator.sol";

contract RandomCPU is ICPU {

    IEngine private immutable ENGINE;

    constructor(IEngine engine) {
        ENGINE = engine;
    }

    /*
    - If it's turn index 0, randomly pick a mon index
    - If it's not turn 0, check for all valid switches (among all mon indices)
    - Check for all valid moves
    - Pick one
    */

    function selectMove(bytes32 battleKey, uint256 playerIndex) external view returns (uint256 moveIndex, bytes memory extraData) {
    }

    function acceptBattle(bytes32 battleKey, uint256 p1TeamIndex, bytes32 battleIntegrityHash) external {
        ENGINE.acceptBattle(battleKey, p1TeamIndex, battleIntegrityHash);
    }
}
