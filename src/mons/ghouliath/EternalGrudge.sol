// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {StatBoosts} from "../../effects/StatBoosts.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";

contract EternalGrudge is IMoveSet {
    int32 public constant ATTACK_DEBUFF_PERCENT = 50;
    int32 public constant SP_ATTACK_DEBUFF_PERCENT = 50;

    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        STAT_BOOSTS = _STAT_BOOSTS;
    }

    function name() public pure override returns (string memory) {
        return "Eternal Grudge";
    }

    function move(bytes32, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        // Apply the debuff
        uint256 defenderPlayerIndex = (attackerPlayerIndex + 1) % 2;
        uint256 defenderMonIndex =
            ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[defenderPlayerIndex];
        STAT_BOOSTS.addStatBoost(
            defenderPlayerIndex,
            defenderMonIndex,
            uint256(MonStateIndexName.Attack),
            ATTACK_DEBUFF_PERCENT,
            StatBoostType.Divide,
            StatBoostFlag.Perm
        );
        STAT_BOOSTS.addStatBoost(
            defenderPlayerIndex,
            defenderMonIndex,
            uint256(MonStateIndexName.SpecialAttack),
            SP_ATTACK_DEBUFF_PERCENT,
            StatBoostType.Divide,
            StatBoostFlag.Perm
        );

        // KO self
        ENGINE.updateMonState(attackerPlayerIndex, defenderMonIndex, MonStateIndexName.IsKnockedOut, 1);
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 2;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Yang;
    }

    function isValidTarget(bytes32, bytes calldata) external pure returns (bool) {
        return true;
    }

    function moveClass(bytes32) public pure returns (MoveClass) {
        return MoveClass.Self;
    }

    function extraDataType() external pure returns (ExtraDataType) {
        return ExtraDataType.None;
    }
}
