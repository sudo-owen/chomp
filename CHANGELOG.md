# Changelog

## Double Battles Implementation

This document summarizes all changes made to implement double battles support.

### Core Data Structure Changes

#### `src/Enums.sol`
- Added `GameMode` enum: `Singles`, `Doubles`

#### `src/Structs.sol`
- **`BattleArgs`** and **`Battle`**: Added `GameMode gameMode` field
- **`BattleData`**: Added `slotSwitchFlagsAndGameMode` (packed field: lower 4 bits = per-slot switch flags, bit 4 = game mode)
- **`BattleContext`** / **`BattleConfigView`**: Added:
  - `p0ActiveMonIndex2`, `p1ActiveMonIndex2` (slot 1 active mons)
  - `slotSwitchFlags` (per-slot switch requirements)
  - `gameMode`

#### `src/Constants.sol`
- Added `GAME_MODE_BIT = 0x10` (bit 4 for doubles mode)
- Added `SWITCH_FLAGS_MASK = 0x0F` (lower 4 bits for per-slot flags)
- Added `ACTIVE_MON_INDEX_MASK = 0x0F` (4 bits per slot in packed active index)

---

### New Files Added

#### `src/DoublesCommitManager.sol`
Commit/reveal manager for doubles that handles **2 moves per player per turn**:
- `commitMoves(battleKey, moveHash)` - Single hash for both moves
- `revealMoves(battleKey, moveIndex0, extraData0, moveIndex1, extraData1, salt, autoExecute)` - Reveal both slot moves
- Validates both moves are legal via `IValidator.validatePlayerMoveForSlot`
- Prevents both slots from switching to same mon (`BothSlotsSwitchToSameMon` error)
- Accounts for cross-slot switch claiming when validating

#### `test/DoublesCommitManagerTest.sol`
Basic integration tests for doubles commit/reveal flow.

#### `test/DoublesValidationTest.sol`
Comprehensive test suite (30 tests) covering:
- Turn 0 switch requirements
- KO'd slot handling with/without valid switch targets
- Both slots KO'd scenarios (0, 1, or 2 reserves)
- Single-player switch turns
- Force-switch moves
- Storage reuse between singles↔doubles transitions

#### `test/mocks/DoublesTargetedAttack.sol`
Mock attack move that targets a specific slot in doubles.

#### `test/mocks/DoublesForceSwitchMove.sol`
Mock move that forces opponent to switch a specific slot (uses `switchActiveMonForSlot`).

---

### Modified Interfaces

#### `src/IEngine.sol`
New functions:
```solidity
// Get active mon index for a specific slot (0 or 1)
function getActiveMonIndexForSlot(bytes32 battleKey, uint256 playerIndex, uint256 slotIndex)
    external view returns (uint256);

// Get game mode (Singles or Doubles)
function getGameMode(bytes32 battleKey) external view returns (GameMode);

// Force-switch a specific slot (for moves like Roar in doubles)
function switchActiveMonForSlot(uint256 playerIndex, uint256 slotIndex, uint256 monToSwitchIndex) external;
```

#### `src/IValidator.sol`
New functions:
```solidity
// Validate a move for a specific slot in doubles
function validatePlayerMoveForSlot(
    bytes32 battleKey, uint256 moveIndex, uint256 playerIndex,
    uint256 slotIndex, uint240 extraData
) external returns (bool);

// Validate accounting for what the other slot is switching to
function validatePlayerMoveForSlotWithClaimed(
    bytes32 battleKey, uint256 moveIndex, uint256 playerIndex,
    uint256 slotIndex, uint240 extraData, uint256 claimedByOtherSlot
) external returns (bool);
```

#### `src/Engine.sol`
Key changes:
- `startBattle` accepts `gameMode` and initializes doubles-specific storage packing
- `execute` dispatches to `_executeDoubles` when in doubles mode
- `_executeDoubles` handles 4 moves per turn (2 per player), speed ordering, KO detection
- `_handleSwitchForSlot` updates slot-specific active mon (4-bit packed storage)
- `_checkForGameOverOrKO_Doubles` checks both slots for each player
- Slot switch flags track which slots need to switch after KOs

#### `src/DefaultValidator.sol`
- `validateSwitch` now checks both slots when in doubles mode
- `validatePlayerMoveForSlot` validates moves for a specific slot
- `validatePlayerMoveForSlotWithClaimed` accounts for cross-slot switch claiming
- `_hasValidSwitchTargetForSlot` / `_hasValidSwitchTargetForSlotWithClaimed` check available mons

---

### Client Usage Guide

#### Starting a Doubles Battle

```solidity
Battle memory battle = Battle({
    p0: alice,
    p1: bob,
    validator: validator,
    rngOracle: rngOracle,
    p0TeamHash: keccak256(abi.encode(teams[0])),
    p1TeamHash: keccak256(abi.encode(teams[1])),
    moveManager: address(doublesCommitManager),  // Use DoublesCommitManager
    matchmaker: matchmaker,
    engineHooks: hooks,
    gameMode: GameMode.Doubles  // Set to Doubles
});

bytes32 battleKey = engine.startBattle(battleArgs);
```

#### Turn 0: Initial Switch (Both Slots)
```solidity
// Alice commits moves for both slots
bytes32 moveHash = keccak256(abi.encodePacked(
    SWITCH_MOVE_INDEX, uint240(0),   // Slot 0 switches to mon 0
    SWITCH_MOVE_INDEX, uint240(1),   // Slot 1 switches to mon 1
    salt
));
doublesCommitManager.commitMoves(battleKey, moveHash);

// Alice reveals
doublesCommitManager.revealMoves(
    battleKey,
    SWITCH_MOVE_INDEX, 0,    // Slot 0: switch to mon 0
    SWITCH_MOVE_INDEX, 1,    // Slot 1: switch to mon 1
    salt,
    true  // autoExecute
);
```

#### Regular Turns: Attacks/Switches
```solidity
// Commit hash of both moves
bytes32 moveHash = keccak256(abi.encodePacked(
    uint8(0), uint240(targetSlot),     // Slot 0: move 0 targeting slot X
    uint8(1), uint240(targetSlot2),    // Slot 1: move 1 targeting slot Y
    salt
));
doublesCommitManager.commitMoves(battleKey, moveHash);

// Reveal
doublesCommitManager.revealMoves(
    battleKey,
    0, uint240(targetSlot),      // Slot 0 move
    1, uint240(targetSlot2),     // Slot 1 move
    salt,
    true
);
```

#### Handling KO'd Slots
- If a slot is KO'd and has valid switch targets → must SWITCH
- If a slot is KO'd and no valid switch targets → must NO_OP (`NO_OP_MOVE_INDEX`)
- If both slots are KO'd with one reserve → slot 0 switches, slot 1 NO_OPs

---

### Future Work / Suggested Changes

#### Target Redirection (Not Yet Implemented)
When a target slot is KO'd mid-turn, moves targeting that slot should redirect or fail. Currently, this can be handled by individual move implementations via an abstract base class.

#### Move Targeting System
- Moves need clear targeting semantics (self, ally slot, opponent slot 0, opponent slot 1, both opponents, etc.)
- Consider adding `TargetType` enum and standardizing `extraData` encoding for slot targeting

#### Speed Tie Handling
- Currently uses basic speed comparison
- May need explicit tie-breaking rules (random, player advantage, etc.)

#### Mixed Switch + Attack Turns
- Implemented and working: during single-player switch turns, the alive slot can attack while the KO'd slot switches
- Test coverage: `test_singlePlayerSwitchTurn_withAttack` verifies attacking during single-player switch turns

#### Ability/Effect Integration
- Abilities that affect both slots (e.g., Intimidate affecting both opponents)
- Weather/terrain affecting 4 mons instead of 2
- Spread moves (hitting multiple targets)

#### UI/Client Considerations
- Clients need to track 4 active mons instead of 2
- Move selection UI needs slot-based targeting
- Battle log should indicate which slot acted
