// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Type, MonStateIndexName, StatBoostType} from "./Enums.sol";
import {IEngineHook} from "./IEngineHook.sol";
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
    address moveManager;
    IMatchmaker matchmaker;
    IEngineHook[] engineHooks;
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
    address moveManager;
    IMatchmaker matchmaker;
    IEngineHook[] engineHooks;
}

struct MoveDecision {
    uint128 moveIndex;
    uint8 isRealTurn; // 1 = real turn, 2 = fake/not set (packed with moveIndex for gas efficiency)
    bytes extraData;
}

// Stored by the Engine, tracks immutable battle data
struct BattleData {
    address p1;
    uint96 startTimestamp;
    address p0;
    IEngineHook[] engineHooks;
}

// Stored by the Engine for a battle, is overwritten after a battle is over
struct BattleConfig {
    IValidator validator;
    IRandomnessOracle rngOracle;
    address moveManager; // Privileged role that can set moves for players outside of execute() call
    uint24 globalEffectsLength;
    uint24 p0EffectsLength;
    uint24 p1EffectsLength;
    uint8 teamSizes; // Packed: lower 4 bits = p0 team size, upper 4 bits = p1 team size (teams arrays may have extra allocated slots)
    bytes32 p0Salt;
    bytes32 p1Salt;
    MoveDecision p0Move;
    MoveDecision p1Move;
    Mon[][] teams;
    MonState[][] monStates;
    mapping(uint256 => EffectInstance) globalEffects;
    mapping(uint256 => EffectInstance) p0Effects;
    mapping(uint256 => EffectInstance) p1Effects;
}

struct EffectInstance {
    IEffect effect;
    uint96 location; // top 8 bits: targetIndex (0/1/2), lower 88 bits: monIndex
    bytes32 data;
}

// View struct for getBattle - contains array instead of mapping for memory return
struct BattleConfigView {
    IValidator validator;
    IRandomnessOracle rngOracle;
    address moveManager;
    uint24 globalEffectsLength;
    uint24 p0EffectsLength;
    uint24 p1EffectsLength;
    uint8 teamSizes;
    bytes32 p0Salt;
    bytes32 p1Salt;
    MoveDecision p0Move;
    MoveDecision p1Move;
    EffectInstance[] globalEffects;
    EffectInstance[] p0Effects;
    EffectInstance[] p1Effects;
    Mon[][] teams;
    MonState[][] monStates;
}

// Stored by the Engine for a battle, tracks mutable battle data
struct BattleState {
    uint8 winnerIndex; // 2 = uninitialized (no winner), 0 = p0 winner, 1 = p1 winner
    uint8 prevPlayerSwitchForTurnFlag;
    uint8 playerSwitchForTurnFlag;
    uint16 activeMonIndex; // Packed: lower 8 bits = player0, upper 8 bits = player1
    uint64 turnId;
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
}

// Used for Commit manager
struct PlayerDecisionData {
    uint16 numMovesRevealed;
    uint16 lastCommitmentTurnId;
    uint96 lastMoveTimestamp;
    bytes32 moveHash;
}

struct RevealedMove {
    uint128 moveIndex;
    bytes32 salt;
    bytes extraData;
}

// Used for StatBoosts
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