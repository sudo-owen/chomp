// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Type} from "./Enums.sol";
import {IRuleset} from "./IRuleset.sol";
import {IValidator} from "./IValidator.sol";
import {IEngineHook} from "./IEngineHook.sol";
import {IAbility} from "./abilities/IAbility.sol";
import {IEffect} from "./effects/IEffect.sol";
import {IMoveSet} from "./moves/IMoveSet.sol";
import {IRandomnessOracle} from "./rng/IRandomnessOracle.sol";
import {ITeamRegistry} from "./teams/ITeamRegistry.sol";
import {IMoveManager} from "./IMoveManager.sol";
import {IMatchmaker} from "./matchmaker/IMatchmaker.sol";

struct ProposedBattle {
    address p0;
    uint96 p0TeamIndex;
    bytes32 p0TeamHash;
    address p1;
    uint96 p1TeamIndex;
    ITeamRegistry teamRegistry;
    IValidator validator;
    IRandomnessOracle rngOracle;
    IRuleset ruleset;
    IEngineHook engineHook;
    IMoveManager moveManager;
    IMatchmaker matchmaker;
}

struct Battle {
    address p0;
    uint96 p0TeamIndex;
    address p1;
    uint96 p1TeamIndex;
    ITeamRegistry teamRegistry;
    IValidator validator;
    IRandomnessOracle rngOracle;
    IRuleset ruleset;
    IEngineHook engineHook;
    IMoveManager moveManager;
    IMatchmaker matchmaker;
    uint96 startTimestamp;
    Mon[][] teams;
}

struct BattleState {
    uint256 turnId;
    uint256[] playerSwitchForTurnFlagHistory;
    uint256 playerSwitchForTurnFlag; // 0 for p0 only move, 1 for p1 only move, 2 for both players
    uint256[] activeMonIndex;
    uint256[] pRNGStream;
    address winner;
    IEffect[] globalEffects;
    bytes[] extraDataForGlobalEffects;
    MonState[][] monStates;
}

struct MonStats {
    uint32 hp;
    uint32 stamina;
    uint32 speed;
    uint32 attack;
    uint32 defense;
    uint32 specialAttack;
    uint32 specialDefense;
    Type type1;
    Type type2;
}

struct Mon {
    MonStats stats;
    IAbility ability;
    IMoveSet[] moves;
}

struct MonState {
    int32 hpDelta;
    int32 staminaDelta;
    int32 speedDelta;
    int32 attackDelta;
    int32 defenceDelta;
    int32 specialAttackDelta;
    int32 specialDefenceDelta;
    bool isKnockedOut; // Is either 0 or 1
    bool shouldSkipTurn; // Used for effects to skip turn, or when moves become invalid (outside of user control)
    // These we can't do much about
    IEffect[] targetedEffects;
    bytes[] extraDataForTargetedEffects;
}

struct Commitment {
    bytes32 moveHash;
    uint256 turnId;
    uint256 timestamp;
}

struct MoveCommitment {
    bytes32 moveHash;
    uint256 turnId;
}

struct RevealedMove {
    uint256 moveIndex;
    bytes32 salt;
    bytes extraData;
}
