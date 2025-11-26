// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";

import "./Enums.sol";
import "./Structs.sol";
import "./moves/IMoveSet.sol";

import {IEngine} from "./IEngine.sol";
import {MappingAllocator} from "./lib/MappingAllocator.sol";
import {IMatchmaker} from "./matchmaker/IMatchmaker.sol";

contract Engine is IEngine, MappingAllocator {
    bytes32 public transient battleKeyForWrite; // intended to be used during call stack by other contracts
    mapping(bytes32 => uint256) public pairHashNonces; // imposes a global ordering across all matches
    mapping(address player => mapping(address maker => bool)) public isMatchmakerFor; // tracks approvals for matchmakers

    mapping(bytes32 => BattleData) private battleData; // These are immutable after a battle begins
    mapping(bytes32 => BattleConfig) private battleConfig; // These exist only throughout the lifecycle of a battle, we reuse these storage slots for subsequent battles
    mapping(bytes32 battleKey => BattleState) private battleStates;
    mapping(bytes32 battleKey => mapping(bytes32 => bytes32)) private globalKV;
    uint256 public transient tempRNG; // Used to provide RNG during execute() tx
    uint256 private transient currentStep; // Used to bubble up step data for events
    address private transient upstreamCaller; // Used to bubble up caller data for events

    // Errors
    error NoWriteAllowed();
    error WrongCaller();
    error MatchmakerNotAuthorized();
    error MatchmakerError();
    error MovesNotSet();
    error InvalidBattleConfig();
    error GameAlreadyOver();

    // Events
    event BattleStart(bytes32 indexed battleKey, address p0, address p1);
    event EngineExecute(
        bytes32 indexed battleKey, uint256 turnId, uint256 playerSwitchForTurnFlag, uint256 priorityPlayerIndex
    );
    event MonSwitch(bytes32 indexed battleKey, uint256 playerIndex, uint256 newMonIndex, address source);
    event MonStateUpdate(
        bytes32 indexed battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        uint256 stateVarIndex,
        int32 valueDelta,
        address source,
        uint256 step
    );
    event MonMove(
        bytes32 indexed battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        uint256 moveIndex,
        bytes extraData,
        int32 staminaCost
    );
    event DamageDeal(
        bytes32 indexed battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        int32 damageDealt,
        address source,
        uint256 step
    );
    event EffectAdd(
        bytes32 indexed battleKey,
        uint256 effectIndex,
        uint256 monIndex,
        address effectAddress,
        bytes extraData,
        address source,
        uint256 step
    );
    event EffectRun(
        bytes32 indexed battleKey,
        uint256 effectIndex,
        uint256 monIndex,
        address effectAddress,
        bytes extraData,
        address source,
        uint256 step
    );
    event EffectEdit(
        bytes32 indexed battleKey,
        uint256 effectIndex,
        uint256 monIndex,
        address effectAddress,
        bytes extraData,
        address source,
        uint256 step
    );
    event EffectRemove(
        bytes32 indexed battleKey,
        uint256 effectIndex,
        uint256 monIndex,
        address effectAddress,
        address source,
        uint256 step
    );
    event BattleComplete(bytes32 indexed battleKey, address winner);
    event EngineEvent(
        bytes32 indexed battleKey, EngineEventType eventType, bytes eventData, address source, uint256 step
    );

    function updateMatchmakers(address[] memory makersToAdd, address[] memory makersToRemove) external {
        for (uint256 i; i < makersToAdd.length; ++i) {
            isMatchmakerFor[msg.sender][makersToAdd[i]] = true;
        }
        for (uint256 i; i < makersToRemove.length; ++i) {
            isMatchmakerFor[msg.sender][makersToRemove[i]] = false;
        }
    }

    function startBattle(Battle memory battle) external {
        // Ensure that the matchmaker is authorized for both players
        IMatchmaker matchmaker = IMatchmaker(battle.matchmaker);
        if (!isMatchmakerFor[battle.p0][address(matchmaker)] || !isMatchmakerFor[battle.p1][address(matchmaker)]) {
            revert MatchmakerNotAuthorized();
        }

        // Compute battle key and update the nonce
        (bytes32 battleKey, bytes32 pairHash) = computeBattleKey(battle.p0, battle.p1);
        pairHashNonces[pairHash] += 1;

        // Ensure that the matchmaker validates the match for both players
        if (!matchmaker.validateMatch(battleKey, battle.p0) || !matchmaker.validateMatch(battleKey, battle.p1)) {
            revert MatchmakerError();
        }

        // Get the storage key for the battle config (reusable)
        bytes32 battleConfigKey = _initializeStorageKey(battleKey);
        BattleConfig storage config = battleConfig[battleConfigKey];

        // Clear previous battle's mon states by setting non-zero values to sentinel
        for (uint256 i = 0; i < config.monStates.length; i++) {
            for (uint256 j = 0; j < config.monStates[i].length; j++) {
                MonState storage monState = config.monStates[i][j];

                // Set all non-zero int32 fields to sentinel value
                if (monState.hpDelta != 0) monState.hpDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.staminaDelta != 0) monState.staminaDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.speedDelta != 0) monState.speedDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.attackDelta != 0) monState.attackDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.defenceDelta != 0) monState.defenceDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.specialAttackDelta != 0) monState.specialAttackDelta = CLEARED_MON_STATE_SENTINEL;
                if (monState.specialDefenceDelta != 0) monState.specialDefenceDelta = CLEARED_MON_STATE_SENTINEL;

                // Reset bools to false
                monState.isKnockedOut = false;
                monState.shouldSkipTurn = false;
            }
        }

        // Store the battle config (update fields individually to preserve allEffects array)
        if (config.validator != battle.validator) {
            config.validator = battle.validator;
        }
        if (config.rngOracle != battle.rngOracle) {
            config.rngOracle = battle.rngOracle;
        }
        if (config.moveManager != battle.moveManager) {
            config.moveManager = battle.moveManager;
        }
        // Reset effectsLength to 0 for the new battle
        config.effectsLength = 0;

        // Store the battle data
        battleData[battleKey] = BattleData({
            p0: battle.p0,
            p1: battle.p1,
            startTimestamp: uint96(block.timestamp),
            engineHooks: battle.engineHooks
        });

        // Set the team for p0 and p1 in the reusable config storage
        // Reuse existing storage slots to keep them warm
        Mon[] memory p0Team = battle.teamRegistry.getTeam(battle.p0, battle.p0TeamIndex);
        Mon[] memory p1Team = battle.teamRegistry.getTeam(battle.p1, battle.p1TeamIndex);

        // Store actual team sizes (packed: lower 4 bits = p0, upper 4 bits = p1)
        config.teamSizes = uint8(p0Team.length) | (uint8(p1Team.length) << 4);

        // Ensure teams array has 2 player slots
        if (config.teams.length < 2) {
            config.teams = new Mon[][](2);
        }

        // Overwrite/resize team arrays for each player
        for (uint256 i = 0; i < 2; i++) {
            Mon[] memory newTeam = (i == 0) ? p0Team : p1Team;

            // Resize if needed by overwriting existing slots or pushing new ones
            if (config.teams[i].length > newTeam.length) {
                // Shrink by overwriting excess slots (we keep them allocated)
                for (uint256 j = 0; j < newTeam.length; j++) {
                    config.teams[i][j] = newTeam[j];
                }
                // Note: We don't pop the excess, just leave them (they'll be ignored based on teamSizes)
            } else {
                // Overwrite existing slots
                for (uint256 j = 0; j < config.teams[i].length; j++) {
                    config.teams[i][j] = newTeam[j];
                }
                // Push new slots if needed
                for (uint256 j = config.teams[i].length; j < newTeam.length; j++) {
                    config.teams[i].push(newTeam[j]);
                }
            }
        }

        // Reuse or initialize mon state arrays
        // Note: activeMonIndex is a packed uint16 that defaults to 0 (both players start with mon index 0)
        if (config.monStates.length < 2) {
            // Need to create the player arrays
            for (uint256 i = config.monStates.length; i < 2; i++) {
                config.monStates.push();
            }
        }

        // For each player, ensure we have enough mon state slots
        for (uint256 i = 0; i < 2; i++) {
            uint256 teamSize = (i == 0) ? (config.teamSizes & 0x0F) : (config.teamSizes >> 4);
            uint256 existingSlots = config.monStates[i].length;

            // Add new slots if needed (existing slots will be reused as-is)
            for (uint256 j = existingSlots; j < teamSize; j++) {
                config.monStates[i].push();
            }
        }

        // Get the global effects and data to start the game if any
        if (address(battle.ruleset) != address(0)) {
            (IEffect[] memory effects, bytes[] memory data) = battle.ruleset.getInitialGlobalEffects();
            if (effects.length > 0) {
                bytes32 storageKey = battleConfigKey;
                BattleConfig storage cfg = battleConfig[storageKey];
                for (uint256 i = 0; i < effects.length; i++) {
                    uint256 effectIndex = cfg.effectsLength;
                    EffectInstance memory newEffect = EffectInstance({
                        effect: effects[i],
                        data: data[i],
                        location: _encodeLocation(2, 0)
                    });
                    // Check if we need to push or can overwrite
                    if (effectIndex < cfg.allEffects.length) {
                        EffectInstance storage existingEffect = cfg.allEffects[effectIndex];
                        if (existingEffect.effect != newEffect.effect) {
                            existingEffect.effect = newEffect.effect;
                        }
                        if (keccak256(existingEffect.data) != keccak256(newEffect.data)) {
                            existingEffect.data = newEffect.data;
                        }
                        if (existingEffect.location != newEffect.location) {
                            existingEffect.location = newEffect.location;
                        }
                    } else {
                        cfg.allEffects.push(newEffect);
                    }
                }
                cfg.effectsLength = uint88(effects.length);
            }
        }

        // Validate the battle config
        if (!battle.validator
                .validateGameStart(battle.p0, battle.p1, config.teams, battle.teamRegistry, battle.p0TeamIndex, battle.p1TeamIndex))
        {
            revert InvalidBattleConfig();
        }

        // Set flag to be 2 which means both players act
        battleStates[battleKey].playerSwitchForTurnFlag = 2;

        // Initialize winnerIndex to 2 (uninitialized/no winner)
        battleStates[battleKey].winnerIndex = 2;

        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onBattleStart(battleKey);
        }

        emit BattleStart(battleKey, battle.p0, battle.p1);
    }

    // THE IMPORTANT FUNCTION
    function execute(bytes32 battleKey) external {
        // Load storage vars
        BattleData storage battle = battleData[battleKey];
        BattleConfig storage config = battleConfig[_getStorageKey(battleKey)];
        BattleState storage state = battleStates[battleKey];

        // Check for game over
        if (state.winnerIndex != 2) {
            revert GameAlreadyOver();
        }

        // Check that at least one move has been set
        if (config.playerMoves[0].isRealTurn != 1 && config.playerMoves[1].isRealTurn != 1) {
            revert MovesNotSet();
        }

        // Set up turn / player vars
        uint256 turnId = state.turnId;
        uint256 playerSwitchForTurnFlag = 2;
        uint256 priorityPlayerIndex;

        // Store the prev player switch for turn flag
        state.prevPlayerSwitchForTurnFlag = state.playerSwitchForTurnFlag;

        // Set the battle key for the stack frame
        // (gets cleared at the end of the transaction)
        battleKeyForWrite = battleKey;

        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onRoundStart(battleKey);
        }

        // If only a single player has a move to submit, then we don't trigger any effects
        // (Basically this only handles switching mons for now)
        if (state.playerSwitchForTurnFlag == 0 || state.playerSwitchForTurnFlag == 1) {
            // Get the player index that needs to switch for this turn
            uint256 playerIndex = state.playerSwitchForTurnFlag;

            // Run the move (trust that the validator only lets valid single player moves happen as a switch action)
            // Running the move will set the winner flag if valid
            playerSwitchForTurnFlag = _handleMove(battleKey, playerIndex, playerSwitchForTurnFlag);
        }
        // Otherwise, we need to run priority calculations and update the game state for both players
        /*
            Flow of battle:
            - Grab moves and calculate pseudo RNG
            - Determine priority player
            - Run round start global effects
            - Run round start targeted effects for p0 and p1
            - Execute priority player's move
            - Check for game over/KO (for switch flag)
                - If game over, just return
            - If KO, skip non priority player's move
            - Execute non priority player's move
            - Check for game over/KO (for switch flag)
                - If game over, just return
            - Run global end of turn effects
            - Check for game over/KO (for switch flag)
                - If game over, just return
            - If not KOed, run the priority player's targeted effects
            - Check for game over/KO (for switch flag)
                - If game over, just return
            - If not KOed, run the non priority player's targeted effects
            - Check for game over/KO (for switch flag)
                - If game over, just return
            - Progress turn index
            - Set player switch for turn flag
        */
        else {

            // Update the temporary RNG to the newest value
            uint256 rng = config.rngOracle.getRNG(config.p0Salt, config.p1Salt);
            tempRNG = rng;

            // Calculate the priority and non-priority player indices
            priorityPlayerIndex = computePriorityPlayerIndex(battleKey, rng);
            uint256 otherPlayerIndex;
            if (priorityPlayerIndex == 0) {
                otherPlayerIndex = 1;
            }

            // Run beginning of round effects
            playerSwitchForTurnFlag = _handleEffects(
                battleKey, rng, 2, 2, EffectStep.RoundStart, EffectRunCondition.SkipIfGameOver, playerSwitchForTurnFlag
            );
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                priorityPlayerIndex,
                priorityPlayerIndex,
                EffectStep.RoundStart,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                otherPlayerIndex,
                otherPlayerIndex,
                EffectStep.RoundStart,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );

            // Run priority player's move (NOTE: moves won't run if either mon is KOed)
            playerSwitchForTurnFlag = _handleMove(battleKey, priorityPlayerIndex, playerSwitchForTurnFlag);

            // If priority mons is not KO'ed, then run the priority player's mon's afterMove hook(s)
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                priorityPlayerIndex,
                priorityPlayerIndex,
                EffectStep.AfterMove,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );

            // Always run the global effect's afterMove hook(s)
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                2,
                priorityPlayerIndex,
                EffectStep.AfterMove,
                EffectRunCondition.SkipIfGameOver,
                playerSwitchForTurnFlag
            );

            // Run the non priority player's move
            playerSwitchForTurnFlag = _handleMove(battleKey, otherPlayerIndex, playerSwitchForTurnFlag);

            // For turn 0 only: wait for both mons to be sent in, then handle the ability activateOnSwitch
            // Happens immediately after both mons are sent in, before any other effects
            if (turnId == 0) {
                uint256 priorityMonIndex = _unpackActiveMonIndex(state.activeMonIndex, priorityPlayerIndex);
                Mon memory priorityMon = config.teams[priorityPlayerIndex][priorityMonIndex];
                if (address(priorityMon.ability) != address(0)) {
                    priorityMon.ability.activateOnSwitch(battleKey, priorityPlayerIndex, priorityMonIndex);
                }
                uint256 otherMonIndex = _unpackActiveMonIndex(state.activeMonIndex, otherPlayerIndex);
                Mon memory otherMon = config.teams[otherPlayerIndex][otherMonIndex];
                if (address(otherMon.ability) != address(0)) {
                    otherMon.ability.activateOnSwitch(battleKey, otherPlayerIndex, otherMonIndex);
                }
            }

            // If non priority mon is not KOed, then run the non priority player's mon's afterMove hook(s)
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                otherPlayerIndex,
                otherPlayerIndex,
                EffectStep.AfterMove,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );

            // Always run the global effect's afterMove hook(s)
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                2,
                otherPlayerIndex,
                EffectStep.AfterMove,
                EffectRunCondition.SkipIfGameOver,
                playerSwitchForTurnFlag
            );

            // Always run global effects at the end of the round
            playerSwitchForTurnFlag = _handleEffects(
                battleKey, rng, 2, 2, EffectStep.RoundEnd, EffectRunCondition.SkipIfGameOver, playerSwitchForTurnFlag
            );

            // If priority mon is not KOed, run roundEnd effects for the priority mon
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                priorityPlayerIndex,
                priorityPlayerIndex,
                EffectStep.RoundEnd,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );

            // If non priority mon is not KOed, run roundEnd effects for the non priority mon
            playerSwitchForTurnFlag = _handleEffects(
                battleKey,
                rng,
                otherPlayerIndex,
                otherPlayerIndex,
                EffectStep.RoundEnd,
                EffectRunCondition.SkipIfGameOverOrMonKO,
                playerSwitchForTurnFlag
            );
        }

        // If a winner has been set, handle the game over
        if (state.winnerIndex != 2) {
            address winner = (state.winnerIndex == 0) ? battle.p0 : battle.p1;
            _handleGameOver(battleKey, winner);
            return;
        }

        // Run the round end hooks
        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onRoundEnd(battleKey);
        }

        // End of turn cleanup:
        // - Progress turn index
        // - Set the player switch for turn flag on state
        // - Clear move flags for next turn (set to 2 = fake/not set)
        state.turnId += 1;
        state.playerSwitchForTurnFlag = uint8(playerSwitchForTurnFlag);
        config.playerMoves[0].isRealTurn = 2;
        config.playerMoves[1].isRealTurn = 2;

        // Emits switch for turn flag for the next turn, but the priority index for this current turn
        emit EngineExecute(battleKey, turnId, playerSwitchForTurnFlag, priorityPlayerIndex);
    }

    function end(bytes32 battleKey) external {
        BattleState storage state = battleStates[battleKey];
        BattleData storage data = battleData[battleKey];
        BattleConfig storage config = battleConfig[_getStorageKey(battleKey)];
        if (state.winnerIndex != 2) {
            revert GameAlreadyOver();
        }
        for (uint256 i; i < 2; ++i) {
            address potentialLoser = config.validator.validateTimeout(battleKey, i);
            if (potentialLoser != address(0)) {
                address winner = potentialLoser == data.p0 ? data.p1 : data.p0;
                state.winnerIndex = (winner == data.p0) ? 0 : 1;
                _handleGameOver(battleKey, winner);
                return;
            }
        }
    }

    function _handleGameOver(bytes32 battleKey, address winner) internal {
        for (uint256 i = 0; i < battleData[battleKey].engineHooks.length; i++) {
            battleData[battleKey].engineHooks[i].onBattleEnd(battleKey);
        }

        // Free the key used for battle configs so other battles can use it
        _freeStorageKey(battleKey);
        emit BattleComplete(battleKey, winner);
    }

    /**
     * - Write functions for MonState, Effects, and GlobalKV
     */
    function updateMonState(uint256 playerIndex, uint256 monIndex, MonStateIndexName stateVarIndex, int32 valueToAdd)
        external
    {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        MonState storage monState = config.monStates[playerIndex][monIndex];
        if (stateVarIndex == MonStateIndexName.Hp) {
            monState.hpDelta = (monState.hpDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.hpDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            monState.staminaDelta = (monState.staminaDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.staminaDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            monState.speedDelta = (monState.speedDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.speedDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            monState.attackDelta = (monState.attackDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.attackDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            monState.defenceDelta = (monState.defenceDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.defenceDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            monState.specialAttackDelta = (monState.specialAttackDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.specialAttackDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            monState.specialDefenceDelta = (monState.specialDefenceDelta == CLEARED_MON_STATE_SENTINEL) ? valueToAdd : monState.specialDefenceDelta + valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.IsKnockedOut) {
            monState.isKnockedOut = (valueToAdd % 2) == 1;
        } else if (stateVarIndex == MonStateIndexName.ShouldSkipTurn) {
            monState.shouldSkipTurn = (valueToAdd % 2) == 1;
        }

        // Grab state update source if it's set and use it, otherwise default to caller
        emit MonStateUpdate(
            battleKey,
            playerIndex,
            monIndex,
            uint256(stateVarIndex),
            valueToAdd,
            _getUpstreamCallerAndResetValue(),
            currentStep
        );

        // Trigger OnUpdateMonState lifecycle hook
        _runEffects(
            battleKey,
            tempRNG,
            playerIndex,
            playerIndex,
            EffectStep.OnUpdateMonState,
            abi.encode(playerIndex, monIndex, stateVarIndex, valueToAdd)
        );
    }

    function addEffect(uint256 targetIndex, uint256 monIndex, IEffect effect, bytes memory extraData) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        if (effect.shouldApply(extraData, targetIndex, monIndex)) {
            bytes memory extraDataToUse = extraData;
            bool removeAfterRun = false;

            // Emit event first, then handle side effects
            emit EffectAdd(
                battleKey,
                targetIndex,
                monIndex,
                address(effect),
                extraData,
                _getUpstreamCallerAndResetValue(),
                uint256(EffectStep.OnApply)
            );

            // Check if we have to run an onApply state update
            if (effect.shouldRunAtStep(EffectStep.OnApply)) {
                // If so, we run the effect first, and get updated extraData if necessary
                (extraDataToUse, removeAfterRun) = effect.onApply(tempRNG, extraData, targetIndex, monIndex);
            }
            if (!removeAfterRun) {
                // Add to unified effects array
                bytes32 storageKey = _getStorageKey(battleKey);
                BattleConfig storage config = battleConfig[storageKey];
                uint256 effectIndex = config.effectsLength;

                EffectInstance memory newEffect = EffectInstance({
                    effect: effect,
                    data: extraDataToUse,
                    location: _encodeLocation(targetIndex, monIndex)
                });

                // Check if we need to push or can overwrite
                if (effectIndex < config.allEffects.length) {
                    // Overwrite existing slot
                    EffectInstance storage existingEffect = config.allEffects[effectIndex];
                    if (existingEffect.effect != newEffect.effect) {
                        existingEffect.effect = newEffect.effect;
                    }
                    if (keccak256(existingEffect.data) != keccak256(newEffect.data)) {
                        existingEffect.data = newEffect.data;
                    }
                    if (existingEffect.location != newEffect.location) {
                        existingEffect.location = newEffect.location;
                    }
                } else {
                    // Need to push new slot
                    config.allEffects.push(newEffect);
                }

                // Increment the effective length
                config.effectsLength = uint88(effectIndex + 1);
            }
        }
    }

    function editEffect(uint256 targetIndex, uint256 monIndex, uint256 effectIndex, bytes memory newExtraData)
        external
    {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }

        // Access the unified effects array
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        EffectInstance storage effectInstance = config.allEffects[effectIndex];

        effectInstance.data = newExtraData;
        emit EffectEdit(
            battleKey,
            targetIndex,
            monIndex,
            address(effectInstance.effect),
            newExtraData,
            _getUpstreamCallerAndResetValue(),
            currentStep
        );
    }

    function removeEffect(uint256 targetIndex, uint256 monIndex, uint256 indexToRemove) public {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }

        // Access the unified effects array
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        EffectInstance[] storage effects = config.allEffects;

        // One last check to see if we should run the final lifecycle hook
        IEffect effect = effects[indexToRemove].effect;
        if (effect.shouldRunAtStep(EffectStep.OnRemove)) {
            effect.onRemove(effects[indexToRemove].data, targetIndex, monIndex);
        }

        // Remove effect instance by swapping with last and decrementing length (no pop)
        uint256 lastIndex = config.effectsLength - 1;
        effects[indexToRemove] = effects[lastIndex];
        config.effectsLength = uint88(lastIndex);

        emit EffectRemove(
            battleKey, targetIndex, monIndex, address(effect), _getUpstreamCallerAndResetValue(), currentStep
        );
    }

    function setGlobalKV(bytes32 key, bytes32 value) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        globalKV[battleKey][key] = value;
    }

    function dealDamage(uint256 playerIndex, uint256 monIndex, int32 damage) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        MonState storage monState = config.monStates[playerIndex][monIndex];

        // If sentinel, replace with -damage; otherwise subtract damage
        monState.hpDelta = (monState.hpDelta == CLEARED_MON_STATE_SENTINEL) ? -damage : monState.hpDelta - damage;

        // Set KO flag if the total hpDelta is greater than the original mon HP
        uint32 baseHp = config.teams[playerIndex][monIndex].stats.hp;
        if (monState.hpDelta + int32(baseHp) <= 0) {
            monState.isKnockedOut = true;
        }
        emit DamageDeal(battleKey, playerIndex, monIndex, damage, _getUpstreamCallerAndResetValue(), currentStep);
        _runEffects(battleKey, tempRNG, playerIndex, playerIndex, EffectStep.AfterDamage, abi.encode(damage));
    }

    function switchActiveMon(uint256 playerIndex, uint256 monToSwitchIndex) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }

        // Use the validator to check if the switch is valid
        if (battleConfig[_getStorageKey(battleKey)].validator.validateSwitch(battleKey, playerIndex, monToSwitchIndex))
        {
            // Only call the internal switch function if the switch is valid
            _handleSwitch(battleKey, playerIndex, monToSwitchIndex, msg.sender);

            // Check for game over and/or KOs for the switching player
            (uint256 playerSwitchForTurnFlag,,, bool isGameOver) = _checkForGameOverOrKO(battleKey, playerIndex);
            if (isGameOver) return;

            // Check for game over and/or KOs for the other player
            uint256 otherPlayerIndex = (playerIndex + 1) % 2;
            (playerSwitchForTurnFlag,,, isGameOver) = _checkForGameOverOrKO(battleKey, otherPlayerIndex);
            if (isGameOver) return;

            // Set the player switch for turn flag
            battleStates[battleKey].playerSwitchForTurnFlag = uint8(playerSwitchForTurnFlag);

            // TODO:
            // Also upstreaming more updates from `_handleSwitch` and change it to also add `_handleEffects`
        }
        // If the switch is invalid, we simply do nothing and continue execution
    }

    function setMove(bytes32 battleKey, uint256 playerIndex, uint128 moveIndex, bytes32 salt, bytes memory extraData)
        external
    {
        bool isMoveManager = msg.sender == address(battleConfig[_getStorageKey(battleKey)].moveManager);
        bool isForCurrentBattle = battleKeyForWrite == battleKey;
        if (!isMoveManager && !isForCurrentBattle) {
            revert NoWriteAllowed();
        }

        // Simply overwrite the move for this player (isRealTurn = 1 means real turn)
        battleConfig[_getStorageKey(battleKey)].playerMoves[playerIndex] =
            MoveDecision({moveIndex: moveIndex, isRealTurn: 1, extraData: extraData});

        if (playerIndex == 0) {
            battleConfig[_getStorageKey(battleKey)].p0Salt = salt;
        } else {
            battleConfig[_getStorageKey(battleKey)].p1Salt = salt;
        }
    }

    function emitEngineEvent(EngineEventType eventType, bytes memory eventData) external {
        bytes32 battleKey = battleKeyForWrite;
        emit EngineEvent(battleKey, eventType, eventData, _getUpstreamCallerAndResetValue(), currentStep);
    }

    function setUpstreamCaller(address caller) external {
        upstreamCaller = caller;
    }

    function computeBattleKey(address p0, address p1) public view returns (bytes32 battleKey, bytes32 pairHash) {
        pairHash = keccak256(abi.encode(p0, p1));
        if (uint256(uint160(p0)) > uint256(uint160(p1))) {
            pairHash = keccak256(abi.encode(p1, p0));
        }
        uint256 pairHashNonce = pairHashNonces[pairHash];
        battleKey = keccak256(abi.encode(pairHash, pairHashNonce));
    }

    function _checkForGameOverOrKO(bytes32 battleKey, uint256 priorityPlayerIndex)
        internal
        returns (
            uint256 playerSwitchForTurnFlag,
            bool isPriorityPlayerActiveMonKnockedOut,
            bool isNonPriorityPlayerActiveMonKnockedOut,
            bool isGameOver
        )
    {
        BattleState storage state = battleStates[battleKey];
        BattleConfig storage config = battleConfig[_getStorageKey(battleKey)];
        uint256 otherPlayerIndex = (priorityPlayerIndex + 1) % 2;
        uint8 existingWinnerIndex = state.winnerIndex;

        // First check if we already calculated a winner
        if (existingWinnerIndex != 2) {
            isGameOver = true;
            return (
                playerSwitchForTurnFlag,
                isPriorityPlayerActiveMonKnockedOut,
                isNonPriorityPlayerActiveMonKnockedOut,
                isGameOver
            );
        }

        // Otherwise, we check the teams of both players
        // A game is over if all of a player's mons are KOed
        uint256 newWinnerIndex = 2;
        uint256[2] memory playerIndices = [uint256(0), uint256(1)];
        for (uint256 i = 0; i < 2; i++) {
            uint256 monsKOed = 0;
            uint256 playerIndex = playerIndices[i];
            uint256 teamSize = (playerIndex == 0) ? (config.teamSizes & 0x0F) : (config.teamSizes >> 4);
            for (uint256 j = 0; j < teamSize; j++) {
                if (config.monStates[playerIndex][j].isKnockedOut) {
                    monsKOed++;
                }
            }
            if (monsKOed == teamSize) {
                newWinnerIndex = uint8((playerIndex + 1) % 2); // winner is the other player
                break;
            }
        }
        // If we found a winner, set it on the state and return
        if (newWinnerIndex != 2) {
            state.winnerIndex = uint8(newWinnerIndex);
            isGameOver = true;
            return (
                playerSwitchForTurnFlag,
                isPriorityPlayerActiveMonKnockedOut,
                isNonPriorityPlayerActiveMonKnockedOut,
                isGameOver
            );
        }
        // Otherwise if it isn't a game over, we check for KOs and set the player switch for turn flag
        else {
            // Always set default switch to be 2 (allow both players to make a move)
            playerSwitchForTurnFlag = 2;

            isPriorityPlayerActiveMonKnockedOut =
            config.monStates[priorityPlayerIndex][_unpackActiveMonIndex(state.activeMonIndex, priorityPlayerIndex)]
            .isKnockedOut;

            isNonPriorityPlayerActiveMonKnockedOut =
            config.monStates[otherPlayerIndex][_unpackActiveMonIndex(state.activeMonIndex, otherPlayerIndex)]
            .isKnockedOut;

            // If the priority player mon is KO'ed (and the other player isn't), then next turn we tenatively set it to be just the other player
            if (isPriorityPlayerActiveMonKnockedOut && !isNonPriorityPlayerActiveMonKnockedOut) {
                playerSwitchForTurnFlag = priorityPlayerIndex;
            }

            // If the non priority player mon is KO'ed (and the other player isn't), then next turn we tenatively set it to be just the priority player
            if (!isPriorityPlayerActiveMonKnockedOut && isNonPriorityPlayerActiveMonKnockedOut) {
                playerSwitchForTurnFlag = otherPlayerIndex;
            }
        }
    }

    function _handleSwitch(bytes32 battleKey, uint256 playerIndex, uint256 monToSwitchIndex, address source) internal {
        // NOTE: We will check for game over after the switch in the engine for two player turns, so we don't do it here
        // But this also means that the current flow of OnMonSwitchOut effects -> OnMonSwitchIn effects -> ability activateOnSwitch
        // will all resolve before checking for KOs or winners
        // (could break this up even more, but that's for a later version / PR)

        bytes32 storageKey = _getStorageKey(battleKey);
        BattleState storage state = battleStates[battleKey];
        BattleConfig storage config = battleConfig[storageKey];
        uint256 currentActiveMonIndex = _unpackActiveMonIndex(state.activeMonIndex, playerIndex);
        MonState storage currentMonState = config.monStates[playerIndex][currentActiveMonIndex];

        // Emit event first, then run effects
        emit MonSwitch(battleKey, playerIndex, monToSwitchIndex, source);

        // If the current mon is not KO'ed
        // Go through each effect to see if it should be cleared after a switch,
        // If so, remove the effect and the extra data
        if (!currentMonState.isKnockedOut) {
            _runEffects(battleKey, tempRNG, playerIndex, playerIndex, EffectStep.OnMonSwitchOut, "");

            // Then run the global on mon switch out hook as well
            _runEffects(battleKey, tempRNG, 2, playerIndex, EffectStep.OnMonSwitchOut, "");
        }

        // Update to new active mon (we assume validateSwitch already resolved and gives us a valid target)
        state.activeMonIndex = _setActiveMonIndex(state.activeMonIndex, playerIndex, monToSwitchIndex);

        // Run onMonSwitchIn hook for local effects
        _runEffects(battleKey, tempRNG, playerIndex, playerIndex, EffectStep.OnMonSwitchIn, "");

        // Run onMonSwitchIn hook for global effects
        _runEffects(battleKey, tempRNG, 2, playerIndex, EffectStep.OnMonSwitchIn, "");

        // Run ability for the newly switched in mon as long as it's not KO'ed and as long as it's not turn 0, (execute() has a special case to run activateOnSwitch after both moves are handled)
        Mon memory mon = config.teams[playerIndex][monToSwitchIndex];
        if (
            address(mon.ability) != address(0) && state.turnId != 0
                && !config.monStates[playerIndex][monToSwitchIndex].isKnockedOut
        ) {
            mon.ability.activateOnSwitch(battleKey, playerIndex, monToSwitchIndex);
        }
    }

    function _handleMove(bytes32 battleKey, uint256 playerIndex, uint256 prevPlayerSwitchForTurnFlag)
        internal
        returns (uint256 playerSwitchForTurnFlag)
    {
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        BattleState storage state = battleStates[battleKey];
        MoveDecision memory move = config.playerMoves[playerIndex];
        int32 staminaCost;
        playerSwitchForTurnFlag = prevPlayerSwitchForTurnFlag;

        // Handle shouldSkipTurn flag first and toggle it off if set
        uint256 activeMonIndex = _unpackActiveMonIndex(state.activeMonIndex, playerIndex);
        MonState storage currentMonState = config.monStates[playerIndex][activeMonIndex];
        if (currentMonState.shouldSkipTurn) {
            currentMonState.shouldSkipTurn = false;
            return playerSwitchForTurnFlag;
        }

        // If we've already determined next turn only one player has to move,
        // this implies the other player has to switch, so we can just short circuit here
        if (prevPlayerSwitchForTurnFlag == 0 || prevPlayerSwitchForTurnFlag == 1) {
            return playerSwitchForTurnFlag;
        }

        // Handle a switch or a no-op
        // otherwise, execute the moveset
        if (move.moveIndex == SWITCH_MOVE_INDEX) {
            // Handle the switch
            _handleSwitch(battleKey, playerIndex, abi.decode(move.extraData, (uint256)), address(0));
        } else if (move.moveIndex == NO_OP_MOVE_INDEX) {
            // Emit event and do nothing (e.g. just recover stamina)
            emit MonMove(battleKey, playerIndex, activeMonIndex, move.moveIndex, move.extraData, staminaCost);
        }
        // Execute the move and then set updated state, active mons, and effects/data
        else {
            // Call validateSpecificMoveSelection again from the validator to ensure that it is still valid to execute
            // If not, then we just return early
            // Handles cases where e.g. some condition outside of the player's control leads to an invalid move
            if (!config.validator.validateSpecificMoveSelection(battleKey, move.moveIndex, playerIndex, move.extraData))
            {
                return playerSwitchForTurnFlag;
            }

            IMoveSet moveSet = config.teams[playerIndex][activeMonIndex].moves[move.moveIndex];

            // Update the mon state directly to account for the stamina cost of the move
            staminaCost = int32(moveSet.stamina(battleKey, playerIndex, activeMonIndex));
            config.monStates[playerIndex][activeMonIndex].staminaDelta -= staminaCost;

            // Emit event and then run the move
            emit MonMove(battleKey, playerIndex, activeMonIndex, move.moveIndex, move.extraData, staminaCost);

            // Run the move (no longer checking for a return value)
            moveSet.move(battleKey, playerIndex, move.extraData, tempRNG);
        }

        // Set Game Over if true, and calculate and return switch for turn flag
        // (We check for both players)
        uint256 otherPlayerIndex = (playerIndex + 1) % 2;
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, playerIndex);
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, otherPlayerIndex);
        return playerSwitchForTurnFlag;
    }

    /**
     * effect index: the target index to filter effects for (0/1/2)
     * player index: the player to pass into the effects args
     */
    function _runEffects(
        bytes32 battleKey,
        uint256 rng,
        uint256 effectIndex,
        uint256 playerIndex,
        EffectStep round,
        bytes memory extraEffectsData
    ) internal {
        BattleState storage state = battleStates[battleKey];
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        EffectInstance[] storage effects = config.allEffects;

        uint256 monIndex;
        // Determine the mon index for the target
        if (effectIndex == 2) {
            // Global effects - monIndex doesn't matter for filtering
            monIndex = 0;
        } else {
            monIndex = _unpackActiveMonIndex(state.activeMonIndex, effectIndex);
        }

        // Grab the active mon (global effect won't know which player index to get, so we set it here)
        if (playerIndex != 2) {
            monIndex = _unpackActiveMonIndex(state.activeMonIndex, playerIndex);
        }

        // Iterate through all effects, filtering by location
        uint256 i;
        uint256 effectsLength = config.effectsLength;

        while (i < effectsLength) {
            // Check if this effect matches our target
            (uint256 effTargetIndex, uint256 effMonIndex) = _decodeLocation(effects[i].location);
            bool playerMonMatch = (effTargetIndex == effectIndex && effMonIndex == monIndex);
            bool isGlobalMatch = (effTargetIndex == 2 && effectIndex == 2);
            bool matches = playerMonMatch || isGlobalMatch;

            if (!matches) {
                ++i;
                continue;
            }
            bool currentStepUpdated;
            if (effects[i].effect.shouldRunAtStep(round)) {
                // Only update the current step if we need to run any effects, and only update it once per step
                if (!currentStepUpdated) {
                    currentStep = uint256(round);
                    currentStepUpdated = true;
                }

                // Emit event first, then handle side effects
                emit EffectRun(
                    battleKey,
                    effectIndex,
                    monIndex,
                    address(effects[i].effect),
                    effects[i].data,
                    _getUpstreamCallerAndResetValue(),
                    currentStep
                );

                // Run the effects (depending on which round stage we are on)
                bytes memory updatedExtraData;
                bool removeAfterRun;
                if (round == EffectStep.RoundStart) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].effect.onRoundStart(rng, effects[i].data, playerIndex, monIndex);
                } else if (round == EffectStep.RoundEnd) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].effect.onRoundEnd(rng, effects[i].data, playerIndex, monIndex);
                } else if (round == EffectStep.OnMonSwitchIn) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].effect.onMonSwitchIn(rng, effects[i].data, playerIndex, monIndex);
                } else if (round == EffectStep.OnMonSwitchOut) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].effect.onMonSwitchOut(rng, effects[i].data, playerIndex, monIndex);
                } else if (round == EffectStep.AfterDamage) {
                    (updatedExtraData, removeAfterRun) = effects[i].effect
                        .onAfterDamage(
                            rng, effects[i].data, playerIndex, monIndex, abi.decode(extraEffectsData, (int32))
                        );
                } else if (round == EffectStep.AfterMove) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].effect.onAfterMove(rng, effects[i].data, playerIndex, monIndex);
                } else if (round == EffectStep.OnUpdateMonState) {
                    (
                        uint256 statePlayerIndex,
                        uint256 stateMonIndex,
                        MonStateIndexName stateVarIndex,
                        int32 valueToAdd
                    ) = abi.decode(extraEffectsData, (uint256, uint256, MonStateIndexName, int32));
                    (updatedExtraData, removeAfterRun) = effects[i].effect
                        .onUpdateMonState(
                            rng, effects[i].data, statePlayerIndex, stateMonIndex, stateVarIndex, valueToAdd
                        );
                }

                // If we remove the effect after doing it, then we clear and update the array
                if (removeAfterRun) {
                    removeEffect(effectIndex, monIndex, i);
                    // After removal, effectsLength decreased, so don't increment i
                    // The effect that was at the end is now at position i
                    effectsLength = config.effectsLength;
                }
                // Otherwise, we update the extra data if e.g. the effect needs to modify its own storage
                else {
                    effects[i].data = updatedExtraData;
                    ++i;
                }
            } else {
                ++i;
            }
        }
    }

    function _handleEffects(
        bytes32 battleKey,
        uint256 rng,
        uint256 effectIndex,
        uint256 playerIndex,
        EffectStep round,
        EffectRunCondition condition,
        uint256 prevPlayerSwitchForTurnFlag
    ) private returns (uint256 playerSwitchForTurnFlag) {
        // Check for Game Over and return early if so
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleState storage state = battleStates[battleKey];
        BattleConfig storage config = battleConfig[storageKey];
        playerSwitchForTurnFlag = prevPlayerSwitchForTurnFlag;
        if (state.winnerIndex != 2) {
            return playerSwitchForTurnFlag;
        }
        // If non-global effect, check if we should still run if mon is KOed
        if (effectIndex != 2) {
            bool isMonKOed =
                config.monStates[playerIndex][_unpackActiveMonIndex(state.activeMonIndex, playerIndex)].isKnockedOut;
            if (isMonKOed && condition == EffectRunCondition.SkipIfGameOverOrMonKO) {
                return playerSwitchForTurnFlag;
            }
        }

        // Otherwise, run the effect
        _runEffects(battleKey, rng, effectIndex, playerIndex, round, "");

        // Set Game Over if true, and calculate and return switch for turn flag
        // (We check for both players)
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, 0);
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, 1);
        return playerSwitchForTurnFlag;
    }

    function computePriorityPlayerIndex(bytes32 battleKey, uint256 rng) public view returns (uint256) {
        BattleConfig storage config = battleConfig[_getStorageKey(battleKey)];
        BattleState storage state = battleStates[battleKey];
        MoveDecision memory p0Move = config.playerMoves[0];
        MoveDecision memory p1Move = config.playerMoves[1];
        uint256 p0ActiveMonIndex = _unpackActiveMonIndex(state.activeMonIndex, 0);
        uint256 p1ActiveMonIndex = _unpackActiveMonIndex(state.activeMonIndex, 1);
        uint256 p0Priority;
        uint256 p1Priority;

        // Call the move for its priority, unless it's the switch or no op move index
        {
            if (p0Move.moveIndex == SWITCH_MOVE_INDEX || p0Move.moveIndex == NO_OP_MOVE_INDEX) {
                p0Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p0MoveSet = config.teams[0][p0ActiveMonIndex].moves[p0Move.moveIndex];
                p0Priority = p0MoveSet.priority(battleKey, 0);
            }

            if (p1Move.moveIndex == SWITCH_MOVE_INDEX || p1Move.moveIndex == NO_OP_MOVE_INDEX) {
                p1Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p1MoveSet = config.teams[1][p1ActiveMonIndex].moves[p1Move.moveIndex];
                p1Priority = p1MoveSet.priority(battleKey, 1);
            }
        }

        // Determine priority based on (in descending order of importance):
        // - the higher priority tier
        // - within same priority, the higher speed
        // - if both are tied, use the rng value
        if (p0Priority > p1Priority) {
            return 0;
        } else if (p0Priority < p1Priority) {
            return 1;
        } else {
            // Calculate speeds by combining base stats with deltas
            uint32 p0MonSpeed = uint32(
                int32(config.teams[0][p0ActiveMonIndex].stats.speed) + config.monStates[0][p0ActiveMonIndex].speedDelta
            );
            uint32 p1MonSpeed = uint32(
                int32(config.teams[1][p1ActiveMonIndex].stats.speed) + config.monStates[1][p1ActiveMonIndex].speedDelta
            );
            if (p0MonSpeed > p1MonSpeed) {
                return 0;
            } else if (p0MonSpeed < p1MonSpeed) {
                return 1;
            } else {
                return rng % 2;
            }
        }
    }

    function _getUpstreamCallerAndResetValue() internal view returns (address) {
        address source = upstreamCaller;
        if (source == address(0)) {
            source = msg.sender;
        }
        return source;
    }

    /**
     * - Helper functions for packing/unpacking activeMonIndex
     */
    function _packActiveMonIndices(uint8 player0Index, uint8 player1Index) internal pure returns (uint16) {
        return uint16(player0Index) | (uint16(player1Index) << 8);
    }

    function _unpackActiveMonIndex(uint16 packed, uint256 playerIndex) internal pure returns (uint256) {
        if (playerIndex == 0) {
            return uint256(uint8(packed));
        } else {
            return uint256(uint8(packed >> 8));
        }
    }

    function _setActiveMonIndex(uint16 packed, uint256 playerIndex, uint256 monIndex) internal pure returns (uint16) {
        if (playerIndex == 0) {
            return (packed & 0xFF00) | uint16(uint8(monIndex));
        } else {
            return (packed & 0x00FF) | (uint16(uint8(monIndex)) << 8);
        }
    }

    /**
     * - Effect location encoding/decoding helpers
     */
    function _encodeLocation(uint256 targetIndex, uint256 monIndex) internal pure returns (uint96) {
        return (uint96(targetIndex) << 88) | uint96(monIndex);
    }

    function _decodeLocation(uint96 location) internal pure returns (uint256 targetIndex, uint256 monIndex) {
        targetIndex = uint256(location >> 88);
        monIndex = uint256(location & ((1 << 88) - 1));
    }

    /**
     * - Effect filtering helper
     */
    function _getEffectsForTarget(bytes32 storageKey, uint256 targetIndex, uint256 monIndex)
        internal
        view
        returns (EffectInstance[] memory, uint256[] memory)
    {
        BattleConfig storage config = battleConfig[storageKey];
        uint256 effectsLength = config.effectsLength;
        EffectInstance[] storage effects = config.allEffects;

        // First pass: count matching effects
        uint256 count = 0;
        for (uint256 i = 0; i < effectsLength; i++) {
            (uint256 effTargetIndex, uint256 effMonIndex) = _decodeLocation(effects[i].location);
            // Include effects that match the target, or global effects (targetIndex == 2)
            if ((effTargetIndex == targetIndex && effMonIndex == monIndex) || effTargetIndex == 2) {
                count++;
            }
        }

        // Second pass: populate result arrays
        EffectInstance[] memory result = new EffectInstance[](count);
        uint256[] memory indices = new uint256[](count);
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < effectsLength; i++) {
            (uint256 effTargetIndex, uint256 effMonIndex) = _decodeLocation(effects[i].location);
            // Include effects that match the target, or global effects (targetIndex == 2)
            if ((effTargetIndex == targetIndex && effMonIndex == monIndex) || effTargetIndex == 2) {
                result[resultIndex] = effects[i];
                indices[resultIndex] = i; // Store the actual index in unified array
                resultIndex++;
            }
        }

        return (result, indices);
    }

    /**
     * - Getters to simplify read access for other components
     */
    function getBattle(bytes32 battleKey) external view returns (BattleConfig memory, BattleData memory) {
        BattleConfig storage config = battleConfig[_getStorageKey(battleKey)];
        BattleData storage data = battleData[battleKey];
        return (config, data);
    }

    function getBattleState(bytes32 battleKey) external view returns (BattleState memory) {
        return battleStates[battleKey];
    }

    function getBattleValidator(bytes32 battleKey) external view returns (IValidator) {
        return battleConfig[_getStorageKey(battleKey)].validator;
    }

    function getMonValueForBattle(
        bytes32 battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        MonStateIndexName stateVarIndex
    ) external view returns (uint32) {
        bytes32 storageKey = _getStorageKey(battleKey);
        if (stateVarIndex == MonStateIndexName.Hp) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.hp;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.stamina;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.speed;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.attack;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.defense;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.specialAttack;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            return battleConfig[storageKey].teams[playerIndex][monIndex].stats.specialDefense;
        } else if (stateVarIndex == MonStateIndexName.Type1) {
            return uint32(battleConfig[storageKey].teams[playerIndex][monIndex].stats.type1);
        } else if (stateVarIndex == MonStateIndexName.Type2) {
            return uint32(battleConfig[storageKey].teams[playerIndex][monIndex].stats.type2);
        } else {
            return 0;
        }
    }

    function getTeamSize(bytes32 battleKey, uint256 playerIndex) external view returns (uint256) {
        bytes32 storageKey = _getStorageKey(battleKey);
        uint8 teamSizes = battleConfig[storageKey].teamSizes;
        return (playerIndex == 0) ? (teamSizes & 0x0F) : (teamSizes >> 4);
    }

    function getMoveForMonForBattle(bytes32 battleKey, uint256 playerIndex, uint256 monIndex, uint256 moveIndex)
        external
        view
        returns (IMoveSet)
    {
        bytes32 storageKey = _getStorageKey(battleKey);
        return battleConfig[storageKey].teams[playerIndex][monIndex].moves[moveIndex];
    }

    function getMoveDecisionForBattleState(bytes32 battleKey, uint256 playerIndex)
        external
        view
        returns (MoveDecision memory)
    {
        return battleConfig[_getStorageKey(battleKey)].playerMoves[playerIndex];
    }

    function getPlayersForBattle(bytes32 battleKey) external view returns (address[] memory) {
        address[] memory players = new address[](2);
        players[0] = battleData[battleKey].p0;
        players[1] = battleData[battleKey].p1;
        return players;
    }

    function getMonStatsForBattle(bytes32 battleKey, uint256 playerIndex, uint256 monIndex)
        external
        view
        returns (MonStats memory)
    {
        bytes32 storageKey = _getStorageKey(battleKey);
        return battleConfig[storageKey].teams[playerIndex][monIndex].stats;
    }

    function getMonStateForBattle(
        bytes32 battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        MonStateIndexName stateVarIndex
    ) external view returns (int32) {
        bytes32 storageKey = _getStorageKey(battleKey);
        BattleConfig storage config = battleConfig[storageKey];
        int32 value;

        if (stateVarIndex == MonStateIndexName.Hp) {
            value = config.monStates[playerIndex][monIndex].hpDelta;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            value = config.monStates[playerIndex][monIndex].staminaDelta;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            value = config.monStates[playerIndex][monIndex].speedDelta;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            value = config.monStates[playerIndex][monIndex].attackDelta;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            value = config.monStates[playerIndex][monIndex].defenceDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            value = config.monStates[playerIndex][monIndex].specialAttackDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            value = config.monStates[playerIndex][monIndex].specialDefenceDelta;
        } else if (stateVarIndex == MonStateIndexName.IsKnockedOut) {
            return config.monStates[playerIndex][monIndex].isKnockedOut ? int32(1) : int32(0);
        } else if (stateVarIndex == MonStateIndexName.ShouldSkipTurn) {
            return config.monStates[playerIndex][monIndex].shouldSkipTurn ? int32(1) : int32(0);
        } else {
            return int32(0);
        }

        // Return 0 if sentinel value is encountered
        return (value == CLEARED_MON_STATE_SENTINEL) ? int32(0) : value;
    }

    function getMonStateForStorageKey(
        bytes32 storageKey,
        uint256 playerIndex,
        uint256 monIndex,
        MonStateIndexName stateVarIndex
    ) external view returns (int32) {
        BattleConfig storage config = battleConfig[storageKey];

        if (stateVarIndex == MonStateIndexName.Hp) {
            return config.monStates[playerIndex][monIndex].hpDelta;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            return config.monStates[playerIndex][monIndex].staminaDelta;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            return config.monStates[playerIndex][monIndex].speedDelta;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            return config.monStates[playerIndex][monIndex].attackDelta;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            return config.monStates[playerIndex][monIndex].defenceDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            return config.monStates[playerIndex][monIndex].specialAttackDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            return config.monStates[playerIndex][monIndex].specialDefenceDelta;
        } else if (stateVarIndex == MonStateIndexName.IsKnockedOut) {
            return config.monStates[playerIndex][monIndex].isKnockedOut ? int32(1) : int32(0);
        } else if (stateVarIndex == MonStateIndexName.ShouldSkipTurn) {
            return config.monStates[playerIndex][monIndex].shouldSkipTurn ? int32(1) : int32(0);
        } else {
            return int32(0);
        }
    }

    function getTurnIdForBattleState(bytes32 battleKey) external view returns (uint256) {
        return battleStates[battleKey].turnId;
    }

    function getActiveMonIndexForBattleState(bytes32 battleKey) external view returns (uint256[] memory) {
        uint16 packed = battleStates[battleKey].activeMonIndex;
        uint256[] memory result = new uint256[](2);
        result[0] = _unpackActiveMonIndex(packed, 0);
        result[1] = _unpackActiveMonIndex(packed, 1);
        return result;
    }

    function getPlayerSwitchForTurnFlagForBattleState(bytes32 battleKey) external view returns (uint256) {
        return battleStates[battleKey].playerSwitchForTurnFlag;
    }

    function getGlobalKV(bytes32 battleKey, bytes32 key) external view returns (bytes32) {
        return globalKV[battleKey][key];
    }

    function getEffects(bytes32 battleKey, uint256 targetIndex, uint256 monIndex)
        external
        view
        returns (EffectInstance[] memory, uint256[] memory)
    {
        bytes32 storageKey = _getStorageKey(battleKey);
        return _getEffectsForTarget(storageKey, targetIndex, monIndex);
    }

    function getWinner(bytes32 battleKey) external view returns (address) {
        uint8 winnerIndex = battleStates[battleKey].winnerIndex;
        if (winnerIndex == 2) {
            return address(0);
        }
        return (winnerIndex == 0) ? battleData[battleKey].p0 : battleData[battleKey].p1;
    }

    function getStartTimestamp(bytes32 battleKey) external view returns (uint256) {
        return battleData[battleKey].startTimestamp;
    }

    function getPrevPlayerSwitchForTurnFlagForBattleState(bytes32 battleKey) external view returns (uint256) {
        return battleStates[battleKey].prevPlayerSwitchForTurnFlag;
    }

    function getMoveManager(bytes32 battleKey) external view returns (address) {
        return battleConfig[_getStorageKey(battleKey)].moveManager;
    }
}
