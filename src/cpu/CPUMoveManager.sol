// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";
import {IMoveManager} from "../IMoveManager.sol";
import {RevealedMove} from "../Structs.sol";
import {ICPU} from "./ICPU.sol";

contract CPUMoveManager is IMoveManager {

    IEngine private immutable ENGINE;
    ICPU private immutable DEFAULT_CPU;

    error NotEngine();

    mapping(bytes32 battleKey => RevealedMove[][]) private moveHistory;
    mapping(address player => ICPU cpu) public cpuForPlayer;

    constructor(IEngine engine, ICPU _DEFAULT_CPU) {
        ENGINE = engine;
        DEFAULT_CPU = _DEFAULT_CPU;
    }

    function selectMove(bytes32 battleKey, uint256 moveIndex, bytes32 salt, bytes calldata extraData) external {
        moveHistory[battleKey][0][ENGINE.getTurnIdForBattleState(battleKey)] = RevealedMove({
            moveIndex: moveIndex,
            salt: salt,
            extraData: extraData
        });
        (uint256 cpuMoveIndex, bytes memory cpuExtraData) = cpuForPlayer[msg.sender].selectMove(battleKey, 1);
        moveHistory[battleKey][1][ENGINE.getTurnIdForBattleState(battleKey)] = RevealedMove({
            moveIndex: cpuMoveIndex,
            salt: salt,
            extraData: cpuExtraData
        });
        ENGINE.execute(battleKey);
    }


    function setCPUForPlayer(address player, ICPU cpu) external {
        cpuForPlayer[player] = cpu;
    }

    // Move manager functions
    function initMoveHistory(bytes32 battleKey) external returns (bool) {
        if (msg.sender != address(ENGINE)) {
            revert NotEngine();
        }
        moveHistory[battleKey].push();
        moveHistory[battleKey].push();
        return true;
    }

    function getMoveForBattleStateForTurn(bytes32 battleKey, uint256 playerIndex, uint256 turn)
        external
        view
        returns (RevealedMove memory)
    {
        return moveHistory[battleKey][playerIndex][turn];
    }

    function getMoveCountForBattleState(bytes32 battleKey, uint256 playerIndex) external view returns (uint256) {
        return moveHistory[battleKey][playerIndex].length;
    }
}
