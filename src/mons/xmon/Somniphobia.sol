// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {NO_OP_MOVE_INDEX, DEFAULT_PRIORITY} from "../../Constants.sol";
import {EffectStep, ExtraDataType, MoveClass, Type} from "../../Enums.sol";
import {MoveDecision, MonStateIndexName, EffectInstance} from "../../Structs.sol";

import {IEngine} from "../../IEngine.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";

contract Somniphobia is IMoveSet, BasicEffect {
    uint256 public constant DURATION = 6;
    int32 public constant DAMAGE_DENOM = 16;

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override(IMoveSet, BasicEffect) returns (string memory) {
        return "Somniphobia";
    }

    function move(bytes32 battleKey, uint256, bytes calldata, uint256) external {
        // Add effect globally for 6 turns (only if it's not already in global effects)
        EffectInstance[] memory effects = ENGINE.getEffects(battleKey, 2, 2);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                return;
            }
        }
        ENGINE.addEffect(2, 2, this, abi.encode(DURATION));
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 3;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Cosmic;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Self;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }

    // Effect implementation
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.AfterMove || step == EffectStep.RoundEnd);
    }

    function onAfterMove(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory, bool)
    {
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        MoveDecision memory moveDecision = ENGINE.getMoveDecisionForBattleStateForTurn(battleKey, targetIndex, turnId);

        // If this player rested (NO_OP), deal damage
        if (moveDecision.moveIndex == NO_OP_MOVE_INDEX) {
            uint32 maxHp = ENGINE.getMonValueForBattle(battleKey, targetIndex, monIndex, MonStateIndexName.Hp);
            int32 damage = int32(uint32(maxHp)) / DAMAGE_DENOM;

            if (damage > 0) {
                ENGINE.dealDamage(targetIndex, monIndex, damage);
            }
        }

        return (extraData, false);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        external
        pure
        override
        returns (bytes memory, bool removeAfterRun)
    {
        uint256 turnsLeft = abi.decode(extraData, (uint256));
        if (turnsLeft == 1) {
            return (extraData, true);
        } else {
            return (abi.encode(turnsLeft - 1), false);
        }
    }
}

