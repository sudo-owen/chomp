// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import "../../Structs.sol";
import {AttackCalculator} from "../../moves/AttackCalculator.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {ITypeCalculator} from "../../types/ITypeCalculator.sol";

contract RockPull is IMoveSet {
    uint32 public constant OPPONENT_BASE_POWER = 80;
    uint32 public constant SELF_DAMAGE_BASE_POWER = 30;

    IEngine immutable ENGINE;
    ITypeCalculator immutable TYPE_CALCULATOR;

    constructor(IEngine _ENGINE, ITypeCalculator _TYPE_CALCULATOR) {
        ENGINE = _ENGINE;
        TYPE_CALCULATOR = _TYPE_CALCULATOR;
    }

    function name() public pure override returns (string memory) {
        return "Rock Pull";
    }

    function _didOtherPlayerChooseSwitch(bytes32 battleKey, uint256 attackerPlayerIndex) internal view returns (bool) {
        // Check RevealedMove for other player
        uint256 otherPlayerIndex = (attackerPlayerIndex + 1) % 2;
        RevealedMove memory otherPlayerMove = ENGINE.getMoveManager(battleKey).getMoveForBattleStateForTurn(
            battleKey, otherPlayerIndex, ENGINE.getTurnIdForBattleState(battleKey)
        );
        return otherPlayerMove.moveIndex == SWITCH_MOVE_INDEX;
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256 rng) external {
        if (_didOtherPlayerChooseSwitch(battleKey, attackerPlayerIndex)) {
            // Deal damage to the opposing mon
            AttackCalculator._calculateDamage(
                ENGINE,
                TYPE_CALCULATOR,
                battleKey,
                attackerPlayerIndex,
                OPPONENT_BASE_POWER,
                DEFAULT_ACCRUACY,
                DEFAULT_VOL,
                moveType(battleKey),
                moveClass(battleKey),
                rng,
                DEFAULT_CRIT_RATE
            );
        } else {
            // Deal damage to ourselves
            (int32 selfDamage, ) = AttackCalculator._calculateDamageView(
                ENGINE,
                TYPE_CALCULATOR,
                battleKey,
                attackerPlayerIndex,
                attackerPlayerIndex,
                SELF_DAMAGE_BASE_POWER,
                DEFAULT_ACCRUACY,
                DEFAULT_VOL,
                moveType(battleKey),
                moveClass(battleKey),
                rng,
                DEFAULT_CRIT_RATE
            );
            uint256[] memory monIndex = ENGINE.getActiveMonIndexForBattleState(battleKey);
            ENGINE.dealDamage(attackerPlayerIndex, monIndex[attackerPlayerIndex], selfDamage);
        }
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 3;
    }

    function priority(bytes32 battleKey, uint256 attackerPlayerIndex) external view returns (uint32) {
        if (_didOtherPlayerChooseSwitch(battleKey, attackerPlayerIndex)) {
            return uint32(SWITCH_PRIORITY) + 1;
        } else {
            return DEFAULT_PRIORITY;
        }
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Earth;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Physical;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}
