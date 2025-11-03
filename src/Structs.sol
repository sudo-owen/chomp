// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Type, MonStateIndexName, StatBoostType, StatBoostFlag} from "./Enums.sol";
import {IEngineHook} from "./IEngineHook.sol";
import {IMoveManager} from "./IMoveManager.sol";
import {IRuleset} from "./IRuleset.sol";
import {IValidator} from "./IValidator.sol";
import {IAbility} from "./abilities/IAbility.sol";
import {IEffect} from "./effects/IEffect.sol";
import {IMatchmaker} from "./matchmaker/IMatchmaker.sol";
import {IMoveSet} from "./moves/IMoveSet.sol";
import {IRandomnessOracle} from "./rng/IRandomnessOracle.sol";
import {ITeamRegistry} from "./teams/ITeamRegistry.sol";

// Used by DefaultMatchmaker
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
    IEngineHook[] engineHooks;
    IMoveManager moveManager;
    IMatchmaker matchmaker;
}

// Used by Engine to initialize a battle's parameters
struct Battle {
    address p0;
    uint96 p0TeamIndex;
    address p1;
    uint96 p1TeamIndex;
    ITeamRegistry teamRegistry;
    IValidator validator;
    IRandomnessOracle rngOracle;
    IRuleset ruleset;
    IMoveManager moveManager;
    IMatchmaker matchmaker;
    IEngineHook[] engineHooks;
}

// Stored by the Engine, tracks immutable battle data
struct BattleData {
    address p0;
    address p1;
    uint96 startTimestamp;
    IEngineHook[] engineHooks;
    Mon[][] teams;
}

// Stored by the Engine for a battle, is overwritten after a battle is over
struct BattleConfig {
    IValidator validator;
    IRandomnessOracle rngOracle;
    IMoveManager moveManager;
}

// Stored by the Engine for a battle, tracks mutable battle data
struct BattleState {
    address winner;
    uint64 turnId;
    uint8 prevPlayerSwitchForTurnFlag;
    uint8 playerSwitchForTurnFlag;
    uint128 p0MonsKOedBitmap;
    uint128 p1MonsKOedBitmap;
    uint256 rng;
    uint16 activeMonIndex; // Packed: lower 8 bits = player0, upper 8 bits = player1
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
    IEffect[] targetedEffects;
    bytes[] extraDataForTargetedEffects;
}

// Used for Commit manager
struct MoveCommitment {
    bytes32 moveHash;
    uint256 turnId;
}

struct RevealedMove {
    uint256 moveIndex;
    bytes32 salt;
    bytes extraData;
}

struct StatBoostToApply {
    MonStateIndexName stat;
    uint8 boostPercent;
    StatBoostType boostType;
}

struct StatBoostUpdate {
    MonStateIndexName stat;
    uint32 oldStat;
    uint32 newStat;
}