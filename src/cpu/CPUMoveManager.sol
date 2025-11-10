// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Constants.sol";
import "../Structs.sol";

import {IEngine} from "../IEngine.sol";
import {ICPU} from "./ICPU.sol";

contract CPUMoveManager {
    IEngine private immutable ENGINE;
    ICPU private immutable DEFAULT_CPU;

    error NotP0();
    error NotEngine();

    mapping(address player => ICPU cpu) public cpuForPlayer;

    constructor(IEngine engine, ICPU _DEFAULT_CPU) {
        ENGINE = engine;
        DEFAULT_CPU = _DEFAULT_CPU;
    }

    function selectMove(bytes32 battleKey, uint128 moveIndex, bytes32 salt, bytes calldata extraData) external {
        if (msg.sender != ENGINE.getPlayersForBattle(battleKey)[0]) {
            revert NotP0();
        }

        BattleState memory battleState = ENGINE.getBattleState(battleKey);
        if (battleState.winnerIndex != 2) {
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

    function _addPlayerMove(bytes32 battleKey, uint128 moveIndex, bytes32 salt, bytes calldata extraData) private {
        ENGINE.setMove(battleKey, 0, moveIndex, salt, extraData);
    }

    function _addCPUMove(bytes32 battleKey, uint128 moveIndex, bytes32 salt, bytes memory extraData) private {
        ENGINE.setMove(battleKey, 1, moveIndex, salt, extraData);
    }

    function _addCPUMoveFromAI(bytes32 battleKey) private {
        ICPU cpu = _getCPUForPlayer(msg.sender);
        (uint128 cpuMoveIndex, bytes memory cpuExtraData) = cpu.selectMove(battleKey, 1);
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

    function getMoveCountForBattleState(bytes32, address) external view returns (uint256) {
        return 0; // TODO: fix later
    }
}
