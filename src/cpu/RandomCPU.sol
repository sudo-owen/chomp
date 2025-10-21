// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";

import {ICPURNG} from "../rng/ICPURNG.sol";
import {CPU} from "./CPU.sol";

import {RevealedMove} from "../Structs.sol";

contract RandomCPU is CPU {
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
        uint256 randomIndex =
            RNG.getRNG(keccak256(abi.encode(nonceToUse++, battleKey, block.timestamp))) % moveChoices.length;
        return (moveChoices[randomIndex].moveIndex, moveChoices[randomIndex].extraData);
    }
}
