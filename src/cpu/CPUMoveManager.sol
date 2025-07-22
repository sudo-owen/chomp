// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Constants.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {IMoveManager} from "../IMoveManager.sol";
import {ICPU} from "./ICPU.sol";

contract CPUMoveManager is IMoveManager {
    IEngine private immutable ENGINE;
    ICPU private immutable DEFAULT_CPU;

    error NotP0();
    error NotEngine();

    mapping(bytes32 battleKey => RevealedMove[][]) private moveHistory;
    mapping(address player => ICPU cpu) public cpuForPlayer;

    constructor(IEngine engine, ICPU _DEFAULT_CPU) {
        ENGINE = engine;
        DEFAULT_CPU = _DEFAULT_CPU;
    }

    function selectMove(bytes32 battleKey, uint256 moveIndex, bytes32 salt, bytes calldata extraData) external {
        if (msg.sender != ENGINE.getPlayersForBattle(battleKey)[0]) {
            revert NotP0();
        }

        BattleState memory battleState = ENGINE.getBattleState(battleKey);
        if (battleState.winner != address(0)) {
            return;
        }

        // Determine move configuration based on turn flag
        if (battleState.playerSwitchForTurnFlag == 0) {
            // P0's turn: player moves, CPU no-ops
            _addPlayerMove(battleKey, moveIndex, salt, extraData);
            _addCPUMove(battleKey, NO_OP_MOVE_INDEX, "", "");
        } else if (battleState.playerSwitchForTurnFlag == 1) {
            // P1's turn: player no-ops, CPU moves
            _addPlayerMove(battleKey, NO_OP_MOVE_INDEX, salt, extraData);
            _addCPUMoveFromAI(battleKey);
        } else {
            // Both players move
            _addPlayerMove(battleKey, moveIndex, salt, extraData);
            _addCPUMoveFromAI(battleKey);
        }

        ENGINE.execute(battleKey);
    }

    function _addPlayerMove(bytes32 battleKey, uint256 moveIndex, bytes32 salt, bytes calldata extraData) private {
        moveHistory[battleKey][0].push(RevealedMove({moveIndex: moveIndex, salt: salt, extraData: extraData}));
    }

    function _addCPUMove(bytes32 battleKey, uint256 moveIndex, bytes32 salt, bytes memory extraData) private {
        moveHistory[battleKey][1].push(RevealedMove({moveIndex: moveIndex, salt: salt, extraData: extraData}));
    }

    function _addCPUMoveFromAI(bytes32 battleKey) private {
        ICPU cpu = _getCPUForPlayer(msg.sender);
        (uint256 cpuMoveIndex, bytes memory cpuExtraData) = cpu.selectMove(battleKey, 1);
        bytes32 cpuSalt = keccak256(abi.encode(battleKey, msg.sender, block.timestamp));
        _addCPUMove(battleKey, cpuMoveIndex, cpuSalt, cpuExtraData);
    }

    function _getCPUForPlayer(address player) private view returns (ICPU) {
        ICPU cpu = cpuForPlayer[player];
        return address(cpu) == address(0) ? DEFAULT_CPU : cpu;
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
