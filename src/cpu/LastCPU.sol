// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";
import {IValidator} from "../IValidator.sol";

import {IMoveSet} from "../moves/IMoveSet.sol";
import {ICPURNG} from "../rng/ICPURNG.sol";
import {ICPU} from "./ICPU.sol";
import {CPU} from "./CPU.sol";

import {NO_OP_MOVE_INDEX, SWITCH_MOVE_INDEX} from "../Constants.sol";

import {ExtraDataType} from "../Enums.sol";
import {Battle, BattleState, RevealedMove} from "../Structs.sol";

contract LastCPU is CPU {

    constructor(uint256 numMoves, IEngine engine, ICPURNG rng) CPU(numMoves, engine, rng) {}

    /**
     * If it's turn 0, randomly selects a mon index to swap to
     *     Otherwise, randomly selects a valid move, switch index, or no op
     */
    function selectMove(bytes32 battleKey, uint256 playerIndex)
        external
        override
        returns (uint256 moveIndex, bytes memory extraData)
    {
        (RevealedMove[] memory moveChoices, uint256 updatedNonce) = calculateValidMoves(battleKey, playerIndex);
        nonceToUse = updatedNonce;
        uint256 choiceIndex = moveChoices.length - 1;
        return (moveChoices[choiceIndex].moveIndex, moveChoices[choiceIndex].extraData);
    }
}
