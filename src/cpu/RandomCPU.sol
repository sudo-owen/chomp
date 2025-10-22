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
        (RevealedMove[] memory moves, RevealedMove[] memory switches, RevealedMove[] memory noOp) = calculateValidMoves(battleKey, playerIndex);

        // Merge all three arrays into one
        uint256 totalChoices = moves.length + switches.length + noOp.length;
        RevealedMove[] memory allChoices = new RevealedMove[](totalChoices);

        uint256 index = 0;
        for (uint256 i = 0; i < moves.length; i++) {
            allChoices[index++] = moves[i];
        }
        for (uint256 i = 0; i < switches.length; i++) {
            allChoices[index++] = switches[i];
        }
        for (uint256 i = 0; i < noOp.length; i++) {
            allChoices[index++] = noOp[i];
        }

        // Select a random move from all choices
        uint256 randomIndex =
            RNG.getRNG(keccak256(abi.encode(nonceToUse++, battleKey, block.timestamp))) % allChoices.length;
        return (allChoices[randomIndex].moveIndex, allChoices[randomIndex].extraData);
    }
}
