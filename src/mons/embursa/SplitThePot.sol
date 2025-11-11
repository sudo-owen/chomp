// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {NO_OP_MOVE_INDEX} from "../../Constants.sol";
import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import {EffectInstance, IEffect, MoveDecision} from "../../Structs.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";

contract SplitThePot is IAbility, BasicEffect {
    int32 public constant HEAL_DENOM = 16;
    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Split The Pot";
    }

    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Check if the effect has already been set for this mon
        EffectInstance[] memory effects = ENGINE.getEffects(battleKey, playerIndex, monIndex);
        for (uint256 i = 0; i < effects.length; i++) {
            if (address(effects[i].effect) == address(this)) {
                return;
            }
        }
        ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), abi.encode(0));
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.AfterMove);
    }

    function onAfterMove(uint256, bytes memory, uint256 targetIndex, uint256)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // If the move index was a no-op, heal all non-KO'ed mons
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 turnId = ENGINE.getTurnIdForBattleState(battleKey);
        MoveDecision memory moveDecision = ENGINE.getMoveDecisionForBattleStateForTurn(battleKey, targetIndex, turnId);
        if (moveDecision.moveIndex == NO_OP_MOVE_INDEX) {
            uint256 teamSize = ENGINE.getTeamSize(battleKey, targetIndex);
            for (uint256 i; i < teamSize; i++) {
                bool isKOed =
                    ENGINE.getMonStateForBattle(battleKey, targetIndex, i, MonStateIndexName.IsKnockedOut) == 1;
                if (!isKOed) {
                    // Calculate base heal amount
                    int32 healAmount =
                        int32(ENGINE.getMonValueForBattle(battleKey, targetIndex, i, MonStateIndexName.Hp)) / HEAL_DENOM;

                    // But don't overheal
                    int32 existingHpDelta = ENGINE.getMonStateForBattle(battleKey, targetIndex, i, MonStateIndexName.Hp);
                    if (existingHpDelta + healAmount > 0) {
                        healAmount = 0 - existingHpDelta;
                    }
                    if (healAmount != 0) {
                        ENGINE.updateMonState(targetIndex, i, MonStateIndexName.Hp, healAmount);
                    }
                }
            }
        }
        return ("", false);
    }
}
