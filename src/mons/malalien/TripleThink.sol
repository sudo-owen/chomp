// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../Constants.sol";
import "../../Enums.sol";

import {IEngine} from "../../IEngine.sol";
import {StatBoosts} from "../../effects/StatBoosts.sol";
import {IMoveSet} from "../../moves/IMoveSet.sol";

contract TripleThink is IMoveSet {
    int32 public constant SP_ATTACK_BUFF_PERCENT = 75;

    IEngine immutable ENGINE;
    StatBoosts immutable STAT_BOOSTS;

    constructor(IEngine _ENGINE, StatBoosts _STAT_BOOSTS) {
        ENGINE = _ENGINE;
        STAT_BOOSTS = _STAT_BOOSTS;
    }

    function name() public pure override returns (string memory) {
        return "Triple Think";
    }

    function move(bytes32 battleKey, uint256 attackerPlayerIndex, bytes calldata, uint256) external {
        // Apply the buff
        STAT_BOOSTS.addStatBoost(
            attackerPlayerIndex,
            ENGINE.getActiveMonIndexForBattleState(battleKey)[attackerPlayerIndex],
            uint256(MonStateIndexName.SpecialAttack),
            SP_ATTACK_BUFF_PERCENT,
            StatBoostType.Multiply,
            StatBoostFlag.Temp
        );
    }

    function stamina(bytes32, uint256, uint256) external pure returns (uint32) {
        return 2;
    }

    function priority(bytes32, uint256) external pure returns (uint32) {
        return DEFAULT_PRIORITY;
    }

    function moveType(bytes32) public pure returns (Type) {
        return Type.Mind;
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
}
