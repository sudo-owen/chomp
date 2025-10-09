// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";

import {ICPURNG} from "../rng/ICPURNG.sol";
import {CPU} from "./CPU.sol";


import {RevealedMove} from "../Structs.sol";

contract PlayerCPU is CPU {

    mapping(bytes32 battleKey => RevealedMove) private declaredMoveForBattle;

    error NotP0();

    constructor(uint256 numMoves, IEngine engine, ICPURNG rng) CPU(numMoves, engine, rng) {}

    function setMove(bytes32 battleKey, uint256 moveIndex, bytes calldata extraData) external {
        if (msg.sender != ENGINE.getPlayersForBattle(battleKey)[0]) {
            revert NotP0();
        }
        declaredMoveForBattle[battleKey] = RevealedMove({
            moveIndex: moveIndex,
            salt: "",
            extraData: extraData
        });
    }

    /**
     * If it's turn 0, randomly selects a mon index to swap to
     *     Otherwise, randomly selects a valid move, switch index, or no op
     */
    function selectMove(bytes32 battleKey, uint256)
        external
        view
        override
        returns (uint256 moveIndex, bytes memory extraData)
    {
        return (declaredMoveForBattle[battleKey].moveIndex, declaredMoveForBattle[battleKey].extraData);
    }
}
