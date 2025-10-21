// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {EffectStep, MonStateIndexName} from "../../Enums.sol";
import {IEngine} from "../../IEngine.sol";
import "../../Structs.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {BasicEffect} from "../../effects/BasicEffect.sol";
import {IEffect} from "../../effects/IEffect.sol";

contract ActusReus is IAbility, BasicEffect {
    IEngine immutable ENGINE;
    int32 public constant SPEED_DEBUFF_DENOM = 2;
    bytes32 public constant INDICTMENT = bytes32("INDICTMENT");

    constructor(IEngine _ENGINE) {
        ENGINE = _ENGINE;
    }

    function name() public pure override(IAbility, BasicEffect) returns (string memory) {
        return "Actus Reus";
    }

    function activateOnSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monIndex) external {
        // Check if the effect has already been set for this mon
        bytes32 monEffectId = keccak256(abi.encode(playerIndex, monIndex, name()));
        if (ENGINE.getGlobalKV(battleKey, monEffectId) != bytes32(0)) {
            return;
        }
        // Otherwise, add this effect to the mon when it switches in
        else {
            uint256 value = 1;
            ENGINE.setGlobalKV(monEffectId, bytes32(value));
            ENGINE.addEffect(playerIndex, monIndex, IEffect(address(this)), abi.encode(0));
        }
    }

    function shouldRunAtStep(EffectStep step) external pure override returns (bool) {
        return (step == EffectStep.AfterMove || step == EffectStep.AfterDamage);
    }

    function getKeyForMonIndex(uint256 targetIndex, uint256 monIndex) public pure returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, name()));
    }

    function _indictmentKey(uint256 targetIndex, uint256 monIndex) public pure returns (bytes32) {
        return keccak256(abi.encode(targetIndex, monIndex, INDICTMENT, name()));
    }

    function getIndictmentFlag(bytes32 battleKey, uint256 targetIndex, uint256 monIndex) public view returns (bytes32) {
        return ENGINE.getGlobalKV(battleKey, _indictmentKey(targetIndex, monIndex));
    }

    function setIndictmentFlag(uint256 targetIndex, uint256 monIndex, bytes32 value) public {
        ENGINE.setGlobalKV(_indictmentKey(targetIndex, monIndex), value);
    }

    function onAfterMove(uint256, bytes memory, uint256 targetIndex, uint256 monIndex)
        external
        override
        returns (bytes memory updatedExtraData, bool removeAfterRun)
    {
        // Check if opposing mon is KOed
        uint256 otherPlayerIndex = (targetIndex + 1) % 2;
        uint256 otherPlayerActiveMonIndex =
            ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[otherPlayerIndex];
        bool isOtherMonKOed =
            ENGINE.getMonStateForBattle(
                ENGINE.battleKeyForWrite(), otherPlayerIndex, otherPlayerActiveMonIndex, MonStateIndexName.IsKnockedOut
            ) == 1;
        if (isOtherMonKOed) {
            if (getIndictmentFlag(ENGINE.battleKeyForWrite(), targetIndex, monIndex) == bytes32(0)) {
                // Set indictment flag for this mon
                setIndictmentFlag(targetIndex, monIndex, bytes32("1"));
            }
        }
        return ("", false);
    }

    function onAfterDamage(uint256, bytes memory, uint256 targetIndex, uint256 monIndex, int32)
        external
        override
        returns (bytes memory, bool)
    {
        // Check if we have an indictment
        if (getIndictmentFlag(ENGINE.battleKeyForWrite(), targetIndex, monIndex) == bytes32("1")) {
            // Reset the indictment flag
            setIndictmentFlag(targetIndex, monIndex, bytes32(0));

            // If we are KO'ed, set a speed delta of half of the opposing mon's base speed
            bool isKOed =
                ENGINE.getMonStateForBattle(
                    ENGINE.battleKeyForWrite(), targetIndex, monIndex, MonStateIndexName.IsKnockedOut
                ) == 1;
            if (isKOed) {
                uint256 otherPlayerIndex = (targetIndex + 1) % 2;
                uint256 otherPlayerActiveMonIndex =
                    ENGINE.getActiveMonIndexForBattleState(ENGINE.battleKeyForWrite())[otherPlayerIndex];
                int32 speedDelta =
                    -1
                    * int32(
                        ENGINE.getMonValueForBattle(
                            ENGINE.battleKeyForWrite(),
                            otherPlayerIndex,
                            otherPlayerActiveMonIndex,
                            MonStateIndexName.Speed
                        )
                    ) / SPEED_DEBUFF_DENOM;
                ENGINE.updateMonState(otherPlayerIndex, otherPlayerActiveMonIndex, MonStateIndexName.Speed, speedDelta);
            }
        }
        return ("", false);
    }
}
