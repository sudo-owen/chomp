// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Constants.sol";

import "./Enums.sol";
import "./Structs.sol";
import "./moves/IMoveSet.sol";

import {IEngine} from "./IEngine.sol";
import {IMoveManager} from "./IMoveManager.sol";
import {IMatchmaker} from "./matchmaker/IMatchmaker.sol";

contract Engine is IEngine {
    // Public state variables
    bytes32 public transient battleKeyForWrite; // intended to be used during call stack by other contracts
    mapping(bytes32 => uint256) public pairHashNonces; // imposes a global ordering across all matches
    mapping(address player => mapping(address maker => bool)) public isMatchmakerFor;

    // Private state variables (battles and battleStates values are granularly accessible via getters)
    mapping(bytes32 battleKey => Battle) private battles;
    mapping(bytes32 battleKey => BattleState) private battleStates;
    mapping(bytes32 battleKey => mapping(bytes32 => bytes32)) private globalKV;
    mapping(bytes32 battleKeyPlusPlayerOffset => uint256) private monsKOedBitmap;
    uint256 private transient currentStep; // Used to bubble up step data for events
    int32 private transient damageDealt; // Used to provide access to onAfterDamage hook for effects
    address private transient upstreamCaller; // Used to bubble up caller data for events

    // Errors
    error NoWriteAllowed();
    error WrongCaller();
    error MatchmakerNotAuthorized();
    error MatchmakerError();
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

        // Store the values in storage
        battles[battleKey] = battle;

        // Set start timestamp
        battles[battleKey].startTimestamp = uint96(block.timestamp);

        // Set the team for p0 and p1
        battles[battleKey].teams[0] = battle.teamRegistry.getTeam(battle.p0, battle.p0TeamIndex);
        battles[battleKey].teams[1] = battle.teamRegistry.getTeam(battle.p1, battle.p1TeamIndex);

        // Initialize empty mon state, move history, and active mon index for each team
        for (uint256 i; i < 2; ++i) {
            battleStates[battleKey].monStates.push();
            battleStates[battleKey].activeMonIndex.push();

            // Initialize empty mon delta states for each mon on the team
            for (uint256 j; j < battles[battleKey].teams[i].length; ++j) {
                battleStates[battleKey].monStates[i].push();
            }
        }

        // Get the global effects and data to start the game if any
        if (address(battle.ruleset) != address(0)) {
            (IEffect[] memory effects, bytes[] memory data) = battle.ruleset.getInitialGlobalEffects();
            if (effects.length > 0) {
                battleStates[battleKey].globalEffects = effects;
                battleStates[battleKey].extraDataForGlobalEffects = data;
            }
        }

        // Validate the battle config
        if (!battle.validator.validateGameStart(battles[battleKey])) {
            revert InvalidBattleConfig();
        }

        // Set flag to be 2 which means both players act
        battleStates[battleKey].playerSwitchForTurnFlag = 2;

        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onBattleStart(battleKey);
        }

        emit BattleStart(battleKey, battle.p0, battle.p1);
    }

    // THE IMPORTANT FUNCTION
    function execute(bytes32 battleKey) external {
        // Load storage vars
        Battle storage battle = battles[battleKey];
        BattleState storage state = battleStates[battleKey];

        // Check for game over
        if (state.winner != address(0)) {
            revert GameAlreadyOver();
        }

        // Set up turn / player vars
        uint256 turnId = state.turnId;
        uint256 playerSwitchForTurnFlag = 2;
        uint256 priorityPlayerIndex;

        // Store the player switch for turn flag history
        state.playerSwitchForTurnFlagHistory.push(state.playerSwitchForTurnFlag);

        // Set the battle key for the stack frame
        // (gets cleared at the end of the transaction)
        battleKeyForWrite = battleKey;

        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onRoundStart(battleKey);
        }

        // If only a single player has a move to submit, then we don't trigger any effects
        // (Basically this only handles switching mons for now)
        if (state.playerSwitchForTurnFlag == 0 || state.playerSwitchForTurnFlag == 1) {
            uint256 rngForSoloTurn = 0;

            // Push 0 to rng stream as only single player is switching, to keep in line with turnId
            state.pRNGStream.push(rngForSoloTurn);

            // Get the player index that needs to switch for this turn
            uint256 playerIndex = state.playerSwitchForTurnFlag;

            // Run the move (trust that the validator only lets valid single player moves happen as a switch action)
            // Running the move will set the winner flag if valid
            playerSwitchForTurnFlag = _handleMove(battleKey, rngForSoloTurn, playerIndex, playerSwitchForTurnFlag);
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
            // Validate both moves have been revealed for the current turn
            // (accessing the values will revert if they haven't been set)
            RevealedMove memory p0Move = battle.moveManager.getMoveForBattleStateForTurn(battleKey, 0, turnId);
            RevealedMove memory p1Move = battle.moveManager.getMoveForBattleStateForTurn(battleKey, 1, turnId);

            // Update the PRNG hash to include the newest value
            uint256 rng = battle.rngOracle.getRNG(p0Move.salt, p1Move.salt);
            state.pRNGStream.push(rng);

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
            playerSwitchForTurnFlag = _handleMove(battleKey, rng, priorityPlayerIndex, playerSwitchForTurnFlag);

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
            playerSwitchForTurnFlag = _handleMove(battleKey, rng, otherPlayerIndex, playerSwitchForTurnFlag);

            // For turn 0 only: wait for both mons to be sent in, then handle the ability activateOnSwitch
            // Happens immediately after both mons are sent in, before any other effects
            if (turnId == 0) {
                Mon memory priorityMon = battle.teams[priorityPlayerIndex][state.activeMonIndex[priorityPlayerIndex]];
                if (address(priorityMon.ability) != address(0)) {
                    priorityMon.ability
                        .activateOnSwitch(battleKey, priorityPlayerIndex, state.activeMonIndex[priorityPlayerIndex]);
                }
                Mon memory otherMon = battle.teams[otherPlayerIndex][state.activeMonIndex[otherPlayerIndex]];
                if (address(otherMon.ability) != address(0)) {
                    otherMon.ability
                        .activateOnSwitch(battleKey, otherPlayerIndex, state.activeMonIndex[otherPlayerIndex]);
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

        // Progress turn index and finally set the player switch for turn flag on the state
        if (state.winner != address(0)) {
            for (uint256 i = 0; i < battle.engineHooks.length; i++) {
                battle.engineHooks[i].onBattleEnd(battleKey);
            }
            return;
        }
        state.turnId += 1;
        state.playerSwitchForTurnFlag = playerSwitchForTurnFlag;

        for (uint256 i = 0; i < battle.engineHooks.length; i++) {
            battle.engineHooks[i].onRoundEnd(battleKey);
        }

        // Emits switch for turn flag for the next turn, but the priority index for this current turn
        emit EngineExecute(battleKey, turnId, playerSwitchForTurnFlag, priorityPlayerIndex);
    }

    function end(bytes32 battleKey) external {
        BattleState storage state = battleStates[battleKey];
        Battle storage battle = battles[battleKey];
        if (state.winner != address(0)) {
            revert GameAlreadyOver();
        }
        for (uint256 i; i < 2; ++i) {
            address potentialLoser = battle.validator.validateTimeout(battleKey, i);
            if (potentialLoser != address(0)) {
                address winner = potentialLoser == battle.p0 ? battle.p1 : battle.p0;
                state.winner = winner;
                for (uint256 j = 0; j < battle.engineHooks.length; j++) {
                    battle.engineHooks[j].onBattleEnd(battleKey);
                }
                emit BattleComplete(battleKey, winner);
                return;
            }
        }
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
        BattleState storage state = battleStates[battleKey];
        MonState storage monState = state.monStates[playerIndex][monIndex];
        if (stateVarIndex == MonStateIndexName.Hp) {
            monState.hpDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            monState.staminaDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            monState.speedDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            monState.attackDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            monState.defenceDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            monState.specialAttackDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            monState.specialDefenceDelta += valueToAdd;
        } else if (stateVarIndex == MonStateIndexName.IsKnockedOut) {
            monState.isKnockedOut = (valueToAdd % 2) == 1;
            // Update the bitmap for the KO flag
            if (valueToAdd % 2 == 1) {
                // Set it to be KOed
                monsKOedBitmap[bytes32(uint256(battleKey) + playerIndex)] |= 1 << monIndex;
            } else {
                // Set it to be not KOed
                monsKOedBitmap[bytes32(uint256(battleKey) + playerIndex)] &= ~(1 << monIndex);
            }
        } else if (stateVarIndex == MonStateIndexName.ShouldSkipTurn) {
            monState.shouldSkipTurn = (valueToAdd % 2) == 1;
        }

        // Grab state update source if it's set and use it, otherwise default to caller
        emit MonStateUpdate(
            battleKey, playerIndex, monIndex, uint256(stateVarIndex), valueToAdd, _getUpstreamCaller(), currentStep
        );
    }

    function addEffect(uint256 targetIndex, uint256 monIndex, IEffect effect, bytes memory extraData) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        if (effect.shouldApply(extraData, targetIndex, monIndex)) {
            BattleState storage state = battleStates[battleKey];
            bytes memory extraDataToUse = extraData;
            bool removeAfterRun = false;

            // Emit event first, then handle side effects
            emit EffectAdd(
                battleKey,
                targetIndex,
                monIndex,
                address(effect),
                extraData,
                _getUpstreamCaller(),
                uint256(EffectStep.OnApply)
            );

            // Check if we have to run an onApply state update
            if (effect.shouldRunAtStep(EffectStep.OnApply)) {
                uint256 rng = state.pRNGStream[state.pRNGStream.length - 1];
                // If so, we run the effect first, and get updated extraData if necessary
                (extraDataToUse, removeAfterRun) = effect.onApply(rng, extraData, targetIndex, monIndex);
            }
            if (!removeAfterRun) {
                if (targetIndex == 2) {
                    state.globalEffects.push(effect);
                    state.extraDataForGlobalEffects.push(extraDataToUse);
                } else {
                    state.monStates[targetIndex][monIndex].targetedEffects.push(effect);
                    state.monStates[targetIndex][monIndex].extraDataForTargetedEffects.push(extraDataToUse);
                }
            }
        }
    }

    function removeEffect(uint256 targetIndex, uint256 monIndex, uint256 indexToRemove) public {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }
        BattleState storage state = battleStates[battleKey];

        // Set the appropriate effects/extra data array from storage
        IEffect[] storage effects;
        bytes[] storage extraData;
        if (targetIndex == 2) {
            effects = state.globalEffects;
            extraData = state.extraDataForGlobalEffects;
        } else {
            effects = state.monStates[targetIndex][monIndex].targetedEffects;
            extraData = state.monStates[targetIndex][monIndex].extraDataForTargetedEffects;
        }

        // One last check to see if we should run the final lifecycle hook
        IEffect effect = effects[indexToRemove];
        if (effect.shouldRunAtStep(EffectStep.OnRemove)) {
            effect.onRemove(extraData[indexToRemove], targetIndex, monIndex);
        }

        // Remove effects and extra data
        uint256 numEffects = effects.length;
        effects[indexToRemove] = effects[numEffects - 1];
        effects.pop();
        extraData[indexToRemove] = extraData[numEffects - 1];
        extraData.pop();
        emit EffectRemove(battleKey, targetIndex, monIndex, address(effect), _getUpstreamCaller(), currentStep);
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
        MonState storage monState = battleStates[battleKey].monStates[playerIndex][monIndex];
        damageDealt = damage;
        monState.hpDelta -= damage;
        // Set KO flag if the total hpDelta is greater than the original mon HP
        uint32 baseHp = battles[battleKey].teams[playerIndex][monIndex].stats.hp;
        if (monState.hpDelta + int32(baseHp) <= 0) {
            monState.isKnockedOut = true;
            monsKOedBitmap[bytes32(uint256(battleKey) + playerIndex)] |= 1 << monIndex;
        }
        uint256[] storage rngValues = battleStates[battleKey].pRNGStream;
        uint256 rngValue = rngValues[rngValues.length - 1];
        emit DamageDeal(battleKey, playerIndex, monIndex, damage, _getUpstreamCaller(), currentStep);
        _runEffects(battleKey, rngValue, playerIndex, playerIndex, EffectStep.AfterDamage);
    }

    function switchActiveMon(uint256 playerIndex, uint256 monToSwitchIndex) external {
        bytes32 battleKey = battleKeyForWrite;
        if (battleKey == bytes32(0)) {
            revert NoWriteAllowed();
        }

        // Use the validator to check if the switch is valid
        if (battles[battleKey].validator.validateSwitch(battleKey, playerIndex, monToSwitchIndex)) {
            // Only call the internal switch function if the switch is valid
            _handleSwitch(battleKey, playerIndex, monToSwitchIndex, msg.sender);

            // Check for game over and/or KOs for the switching player
            (uint256 playerSwitchForTurnFlag,,, bool isGameOver) = _checkForGameOverOrKO(battleKey, playerIndex);
            if (isGameOver) return;

            // Set the player switch for turn flag
            battleStates[battleKey].playerSwitchForTurnFlag = playerSwitchForTurnFlag;

            // TODO: consider also checking game over / setting flag for other player
            // Also upstreaming more updates from `_handleSwitch` and change it to also add `_handleEffects`
        }
        // If the switch is invalid, we simply do nothing and continue execution
    }

    function emitEngineEvent(EngineEventType eventType, bytes memory eventData) external {
        bytes32 battleKey = battleKeyForWrite;
        emit EngineEvent(battleKey, eventType, eventData, _getUpstreamCaller(), currentStep);
    }

    function setUpstreamCaller(address caller) external {
        upstreamCaller = caller;
    }

    /**
     * - Internal helper functions
     */
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
        Battle storage battle = battles[battleKey];
        BattleState storage state = battleStates[battleKey];
        uint256 otherPlayerIndex = (priorityPlayerIndex + 1) % 2;
        address gameResult = battle.validator.validateGameOver(battleKey, priorityPlayerIndex);
        if (gameResult != address(0)) {
            // Ensure we only emit the event / update the state once (we may call this multiple times during one stack frame)
            if (state.winner == address(0)) {
                state.winner = gameResult;
                emit BattleComplete(battleKey, gameResult);
            }
            isGameOver = true;
        } else {
            // Always set default switch to be 2 (allow both players to make a move)
            playerSwitchForTurnFlag = 2;

            isPriorityPlayerActiveMonKnockedOut =
                state.monStates[priorityPlayerIndex][state.activeMonIndex[priorityPlayerIndex]].isKnockedOut;

            isNonPriorityPlayerActiveMonKnockedOut =
                state.monStates[otherPlayerIndex][state.activeMonIndex[otherPlayerIndex]].isKnockedOut;

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

        BattleState storage state = battleStates[battleKey];
        MonState storage currentMonState = state.monStates[playerIndex][state.activeMonIndex[playerIndex]];
        uint256 rng = state.pRNGStream[state.pRNGStream.length - 1];

        // Emit event first, then run effects
        emit MonSwitch(battleKey, playerIndex, monToSwitchIndex, source);

        // If the current mon is not KO'ed
        // Go through each effect to see if it should be cleared after a switch,
        // If so, remove the effect and the extra data
        if (!currentMonState.isKnockedOut) {
            _runEffects(battleKey, rng, playerIndex, playerIndex, EffectStep.OnMonSwitchOut);

            // Then run the global on mon switch out hook as well
            _runEffects(battleKey, rng, 2, playerIndex, EffectStep.OnMonSwitchOut);
        }

        // Update to new active mon (we assume validateSwitch already resolved and gives us a valid target)
        state.activeMonIndex[playerIndex] = monToSwitchIndex;

        // Run onMonSwitchIn hook for local effects
        _runEffects(battleKey, rng, playerIndex, playerIndex, EffectStep.OnMonSwitchIn);

        // Run onMonSwitchIn hook for global effects
        _runEffects(battleKey, rng, 2, playerIndex, EffectStep.OnMonSwitchIn);

        // Run ability for the newly switched in mon (as long as it's not turn 0, execute() has a special case to run activateOnSwitch after both moves are handled)
        Mon memory mon = battles[battleKey].teams[playerIndex][monToSwitchIndex];
        if (address(mon.ability) != address(0) && state.turnId != 0) {
            mon.ability.activateOnSwitch(battleKey, playerIndex, monToSwitchIndex);
        }
    }

    function _handleMove(bytes32 battleKey, uint256 rng, uint256 playerIndex, uint256 prevPlayerSwitchForTurnFlag)
        internal
        returns (uint256 playerSwitchForTurnFlag)
    {
        Battle storage battle = battles[battleKey];
        BattleState storage state = battleStates[battleKey];
        RevealedMove memory move = battle.moveManager.getMoveForBattleStateForTurn(battleKey, playerIndex, state.turnId);
        int32 staminaCost;
        playerSwitchForTurnFlag = prevPlayerSwitchForTurnFlag;

        // Handle shouldSkipTurn flag first and toggle it off if set
        MonState storage currentMonState = state.monStates[playerIndex][state.activeMonIndex[playerIndex]];
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
            emit MonMove(
                battleKey, playerIndex, state.activeMonIndex[playerIndex], move.moveIndex, move.extraData, staminaCost
            );
        }
        // Execute the move and then set updated state, active mons, and effects/data
        else {
            // Call validateSpecificMoveSelection again from the validator to ensure that it is still valid to execute
            // If not, then we just return early
            // Handles cases where e.g. some condition outside of the player's control leads to an invalid move
            if (!battle.validator.validateSpecificMoveSelection(battleKey, move.moveIndex, playerIndex, move.extraData))
            {
                return playerSwitchForTurnFlag;
            }

            IMoveSet moveSet = battle.teams[playerIndex][state.activeMonIndex[playerIndex]].moves[move.moveIndex];

            // Update the mon state directly to account for the stamina cost of the move
            staminaCost = int32(moveSet.stamina(battleKey, playerIndex, state.activeMonIndex[playerIndex]));
            state.monStates[playerIndex][state.activeMonIndex[playerIndex]].staminaDelta -= staminaCost;

            // Emit event and then run the move
            emit MonMove(
                battleKey, playerIndex, state.activeMonIndex[playerIndex], move.moveIndex, move.extraData, staminaCost
            );

            // Run the move (no longer checking for a return value)
            moveSet.move(battleKey, playerIndex, move.extraData, rng);
        }

        // Set Game Over if true, and calculate and return switch for turn flag
        // (We check for both players)
        uint256 otherPlayerIndex = (playerIndex + 1) % 2;
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, playerIndex);
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, otherPlayerIndex);
        return playerSwitchForTurnFlag;
    }

    /**
     * effect index: the index to grab the relevant effect array
     *    player index: the player to pass into the effects args
     */
    function _runEffects(bytes32 battleKey, uint256 rng, uint256 effectIndex, uint256 playerIndex, EffectStep round)
        internal
    {
        BattleState storage state = battleStates[battleKey];
        IEffect[] storage effects;
        bytes[] storage extraData;
        uint256 monIndex;
        // Switch between global or targeted effects array depending on the args
        if (effectIndex == 2) {
            effects = state.globalEffects;
            extraData = state.extraDataForGlobalEffects;
        } else {
            monIndex = state.activeMonIndex[effectIndex];
            effects = state.monStates[effectIndex][monIndex].targetedEffects;
            extraData = state.monStates[effectIndex][monIndex].extraDataForTargetedEffects;
        }
        // Grab the active mon (global effect won't know which player index to get, so we set it here)
        if (playerIndex != 2) {
            monIndex = state.activeMonIndex[playerIndex];
        }
        uint256 i;
        while (i < effects.length) {
            bool currentStepUpdated;
            if (effects[i].shouldRunAtStep(round)) {
                // Only update the current step if we need to run any effects, and only update it once per step
                if (!currentStepUpdated) {
                    currentStep = uint256(round);
                    currentStepUpdated = true;
                }

                // Run the effects (depending on which round stage we are on)
                bytes memory updatedExtraData;
                bool removeAfterRun;
                if (round == EffectStep.RoundStart) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].onRoundStart(rng, extraData[i], playerIndex, monIndex);
                } else if (round == EffectStep.RoundEnd) {
                    (updatedExtraData, removeAfterRun) = effects[i].onRoundEnd(rng, extraData[i], playerIndex, monIndex);
                } else if (round == EffectStep.OnMonSwitchIn) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].onMonSwitchIn(rng, extraData[i], playerIndex, monIndex);
                } else if (round == EffectStep.OnMonSwitchOut) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].onMonSwitchOut(rng, extraData[i], playerIndex, monIndex);
                } else if (round == EffectStep.AfterDamage) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].onAfterDamage(rng, extraData[i], playerIndex, monIndex, damageDealt);
                } else if (round == EffectStep.AfterMove) {
                    (updatedExtraData, removeAfterRun) =
                        effects[i].onAfterMove(rng, extraData[i], playerIndex, monIndex);
                }

                // If we remove the effect after doing it, then we clear and update the array/extra data
                if (removeAfterRun) {
                    removeEffect(effectIndex, monIndex, i);
                }
                // Otherwise, we update the extra data if e.g. the effect needs to modify its own storage
                else {
                    extraData[i] = updatedExtraData;
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
        BattleState storage state = battleStates[battleKey];
        playerSwitchForTurnFlag = prevPlayerSwitchForTurnFlag;
        if (state.winner != address(0)) {
            return playerSwitchForTurnFlag;
        }
        // If non-global effect, check if we should still run if mon is KOed
        if (effectIndex != 2) {
            bool isMonKOed = state.monStates[playerIndex][state.activeMonIndex[playerIndex]].isKnockedOut;
            if (isMonKOed && condition == EffectRunCondition.SkipIfGameOverOrMonKO) {
                return playerSwitchForTurnFlag;
            }
        }

        // Otherwise, run the effect
        _runEffects(battleKey, rng, effectIndex, playerIndex, round);

        // Set Game Over if true, and calculate and return switch for turn flag
        // (We check for both players)
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, 0);
        (playerSwitchForTurnFlag,,,) = _checkForGameOverOrKO(battleKey, 1);
        return playerSwitchForTurnFlag;
    }

    function computePriorityPlayerIndex(bytes32 battleKey, uint256 rng) public view returns (uint256) {
        Battle storage battle = battles[battleKey];
        BattleState storage state = battleStates[battleKey];
        RevealedMove memory p0Move = battle.moveManager.getMoveForBattleStateForTurn(battleKey, 0, state.turnId);
        RevealedMove memory p1Move = battle.moveManager.getMoveForBattleStateForTurn(battleKey, 1, state.turnId);
        uint256 p0ActiveMonIndex = state.activeMonIndex[0];
        uint256 p1ActiveMonIndex = state.activeMonIndex[1];
        uint256 p0Priority;
        uint256 p1Priority;

        // Call the move for its priority, unless it's the switch or no op move index
        {
            if (p0Move.moveIndex == SWITCH_MOVE_INDEX || p0Move.moveIndex == NO_OP_MOVE_INDEX) {
                p0Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p0MoveSet = battle.teams[0][p0ActiveMonIndex].moves[p0Move.moveIndex];
                p0Priority = p0MoveSet.priority(battleKey, 0);
            }

            if (p1Move.moveIndex == SWITCH_MOVE_INDEX || p1Move.moveIndex == NO_OP_MOVE_INDEX) {
                p1Priority = SWITCH_PRIORITY;
            } else {
                IMoveSet p1MoveSet = battle.teams[1][p1ActiveMonIndex].moves[p1Move.moveIndex];
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
                int32(battle.teams[0][p0ActiveMonIndex].stats.speed) + state.monStates[0][p0ActiveMonIndex].speedDelta
            );
            uint32 p1MonSpeed = uint32(
                int32(battle.teams[1][p1ActiveMonIndex].stats.speed) + state.monStates[1][p1ActiveMonIndex].speedDelta
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

    function _getUpstreamCaller() internal view returns (address) {
        address source = upstreamCaller;
        if (source == address(0)) {
            source = msg.sender;
        }
        return source;
    }

    /**
     * - Getters to simplify read access for other components
     */

    // getBattle and getBattleState are intended to be consumed by offchain clients
    function getBattle(bytes32 battleKey) external view returns (Battle memory) {
        return battles[battleKey];
    }

    function getBattleState(bytes32 battleKey) external view returns (BattleState memory) {
        return battleStates[battleKey];
    }

    function getBattleValidator(bytes32 battleKey) external view returns (IValidator) {
        return battles[battleKey].validator;
    }

    function getMonValueForBattle(
        bytes32 battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        MonStateIndexName stateVarIndex
    ) external view returns (uint32) {
        if (stateVarIndex == MonStateIndexName.Hp) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.hp;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.stamina;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.speed;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.attack;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.defense;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.specialAttack;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            return battles[battleKey].teams[playerIndex][monIndex].stats.specialDefense;
        } else if (stateVarIndex == MonStateIndexName.Type1) {
            return uint32(battles[battleKey].teams[playerIndex][monIndex].stats.type1);
        } else if (stateVarIndex == MonStateIndexName.Type2) {
            return uint32(battles[battleKey].teams[playerIndex][monIndex].stats.type2);
        } else {
            return 0;
        }
    }

    function getTeamSize(bytes32 battleKey, uint256 playerIndex) external view returns (uint256) {
        return battles[battleKey].teams[playerIndex].length;
    }

    function getMoveForMonForBattle(bytes32 battleKey, uint256 playerIndex, uint256 monIndex, uint256 moveIndex)
        external
        view
        returns (IMoveSet)
    {
        return battles[battleKey].teams[playerIndex][monIndex].moves[moveIndex];
    }

    function getPlayersForBattle(bytes32 battleKey) external view returns (address[] memory) {
        address[] memory players = new address[](2);
        players[0] = battles[battleKey].p0;
        players[1] = battles[battleKey].p1;
        return players;
    }

    function getMonStateForBattle(
        bytes32 battleKey,
        uint256 playerIndex,
        uint256 monIndex,
        MonStateIndexName stateVarIndex
    ) external view returns (int32) {
        if (stateVarIndex == MonStateIndexName.Hp) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].hpDelta;
        } else if (stateVarIndex == MonStateIndexName.Stamina) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].staminaDelta;
        } else if (stateVarIndex == MonStateIndexName.Speed) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].speedDelta;
        } else if (stateVarIndex == MonStateIndexName.Attack) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].attackDelta;
        } else if (stateVarIndex == MonStateIndexName.Defense) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].defenceDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialAttack) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].specialAttackDelta;
        } else if (stateVarIndex == MonStateIndexName.SpecialDefense) {
            return battleStates[battleKey].monStates[playerIndex][monIndex].specialDefenceDelta;
        } else if (stateVarIndex == MonStateIndexName.IsKnockedOut) {
            if (battleStates[battleKey].monStates[playerIndex][monIndex].isKnockedOut) {
                return 1;
            } else {
                return 0;
            }
        } else if (stateVarIndex == MonStateIndexName.ShouldSkipTurn) {
            if (battleStates[battleKey].monStates[playerIndex][monIndex].shouldSkipTurn) {
                return 1;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    function getTurnIdForBattleState(bytes32 battleKey) external view returns (uint256) {
        return battleStates[battleKey].turnId;
    }

    function getActiveMonIndexForBattleState(bytes32 battleKey) external view returns (uint256[] memory) {
        return battleStates[battleKey].activeMonIndex;
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
        returns (IEffect[] memory, bytes[] memory)
    {
        BattleState storage state = battleStates[battleKey];
        if (targetIndex == 2) {
            return (state.globalEffects, state.extraDataForGlobalEffects);
        } else {
            return (
                state.monStates[targetIndex][monIndex].targetedEffects,
                state.monStates[targetIndex][monIndex].extraDataForTargetedEffects
            );
        }
    }

    function getMonKOCount(bytes32 battleKey, uint256 playerIndex) external view returns (uint256) {
        return monsKOedBitmap[bytes32(uint256(battleKey) + playerIndex)];
    }

    function getWinner(bytes32 battleKey) external view returns (address) {
        return battleStates[battleKey].winner;
    }

    function getStartTimestamp(bytes32 battleKey) external view returns (uint256) {
        return battles[battleKey].startTimestamp;
    }

    function getRNG(bytes32 battleKey, uint256 index) external view returns (uint256) {
        if (index == type(uint256).max) {
            return battleStates[battleKey].pRNGStream[battleStates[battleKey].pRNGStream.length - 1];
        }
        return battleStates[battleKey].pRNGStream[index];
    }

    function getPlayerSwitchForTurnFlagHistory(bytes32 battleKey) external view returns (uint256[] memory) {
        return battleStates[battleKey].playerSwitchForTurnFlagHistory;
    }

    function getMoveManager(bytes32 battleKey) external view returns (IMoveManager) {
        return battles[battleKey].moveManager;
    }
}
