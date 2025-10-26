// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {IEffect} from "../../effects/IEffect.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";

contract IronWall is IMoveSet, BasicEffect {
    int32 public constant HEAL_PERCENT = 50; // Heal 50% of damage taken

    IEngine immutable ENGINE;

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override returns (string memory) {
        return "Iron Wall";
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        // Get the current turn
        uint256 currentTurn = ENGINE.getTurnIdForBattleState(battleKey);

        // Get the active mon index
        uint256 activeMonIndex = ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex];

        // Add the effect to Aurox with the activation turn stored in extraData
        // The effect will last until the end of turn (currentTurn + 1)
        ENGINE.addEffect(attackerPlayerIndex, activeMonIndex, IEffect(address(this)), abi.encode(currentTurn));
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 2;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Metal;
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

    // IEffect implementation
    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.AfterDamage || step == EffectStep.RoundEnd);
    }

    function onAfterDamage(uint256, bytes memory extraData, uint256 targetIndex, uint256 monIndex, int32 damageDealt)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Heal 50% of the damage taken
        int32 healAmount = (damageDealt * HEAL_PERCENT) / 100;

        if (healAmount > 0) {
            ENGINE.updateMonState(targetIndex, monIndex, MonStateIndexName.Hp, healAmount);
        }

        return (extraData, false);
    }

    function onRoundEnd(uint256, bytes memory extraData, uint256, uint256)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Decode the activation turn from extraData
        uint256 activationTurn = abi.decode(extraData, (uint256));

        // Get the current turn
        uint256 currentTurn = ENGINE.getTurnIdForBattleState(ENGINE.battleKeyForWrite());

        // Remove the effect at the end of turn (activationTurn + 1)
        if (currentTurn > activationTurn) {
            return (extraData, true);
        }

        return (extraData, false);
    }
}
