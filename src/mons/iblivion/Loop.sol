// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Enums.sol";
import "../../Constants.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {IEngine} from "../../IEngine.sol";

contract Loop is IMoveSet {

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override returns (string memory) {
        return "Loop";
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];
        int32 currentStaminaDelta = ENGINE.getMonStateForBattle(battleKey, attackerPlayerIndex, activeMonIndex, MonStateIndexName.Stamina);
        if (currentStaminaDelta > 0) {
            return;
        }
        // Reset all stamina costs
        int32 staminaToHeal = -1 * currentStaminaDelta;
        ENGINE.updateMonState(attackerPlayerIndex, activeMonIndex, MonStateIndexName.Stamina, staminaToHeal);
    }

    function stamina(bytes32, uint256, uint256 ) external pure returns (uint32) {
        return 1;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Yin;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Self;
    }
}