# Test Migration Guide: Engine Challenge Flow Refactor

## Overview

The challenge flow has been moved from the `Engine` contract to the `DefaultMatchmaker` contract. This document outlines the changes needed to migrate existing tests.

## What Changed

### Old Flow (Engine-based)
```solidity
// 1. Propose battle
Battle memory args = Battle({...});
vm.startPrank(ALICE);
bytes32 battleKey = engine.proposeBattle(args);

// 2. Accept battle
bytes32 battleIntegrityHash = keccak256(abi.encodePacked(...));
vm.startPrank(BOB);
engine.acceptBattle(battleKey, 0, battleIntegrityHash);

// 3. Start battle
vm.startPrank(ALICE);
engine.startBattle(battleKey, "", 0);
```

### New Flow (Matchmaker-based - Manual)
```solidity
// 0. Both players authorize matchmaker (on Engine)
vm.startPrank(ALICE);
engine.authorizeMatchmaker([address(matchmaker)], []);
vm.startPrank(BOB);
engine.authorizeMatchmaker([address(matchmaker)], []);

// 1. Propose battle
ProposedBattle memory proposal = ProposedBattle({...});
vm.startPrank(ALICE);
bytes32 battleKey = matchmaker.proposeBattle(proposal);

// 2. Accept battle
bytes32 battleIntegrityHash = matchmaker.getBattleProposalIntegrityHash(proposal);
vm.startPrank(BOB);
matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);

// 3. Confirm and start battle
vm.startPrank(ALICE);
matchmaker.confirmBattle(battleKey, salt, p0TeamIndex);
```

### New Flow (Using BattleHelper)
```solidity
// BattleHelper handles authorization, proposal, acceptance, and confirmation automatically!
bytes32 battleKey = _startBattle(validator, engine, rngOracle, defaultRegistry, matchmaker);
```

## BattleHelper.sol Changes

✅ **COMPLETED** - The `BattleHelper` abstract contract has been updated with new `_startBattle()` overloads that:
- Require a `DefaultMatchmaker` parameter
- **Handle matchmaker authorization automatically** (calls `engine.authorizeMatchmaker()` for both players)
- Use `ProposedBattle` struct instead of `Battle`
- Call the matchmaker's propose/accept/confirm flow
- **Tests using BattleHelper don't need to call `engine.authorizeMatchmaker()` directly**

## Migration Steps for Tests Using BattleHelper

### Step 1: Add DefaultMatchmaker to Setup

**Before:**
```solidity
contract MyTest is Test, BattleHelper {
    Engine engine;
    FastCommitManager commitManager;
    TestTeamRegistry defaultRegistry;
    
    function setUp() public {
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        defaultRegistry = new TestTeamRegistry();
    }
}
```

**After:**
```solidity
import {DefaultMatchmaker} from "../../src/matchmaker/DefaultMatchmaker.sol";

contract MyTest is Test, BattleHelper {
    Engine engine;
    FastCommitManager commitManager;
    TestTeamRegistry defaultRegistry;
    DefaultMatchmaker matchmaker;  // ADD THIS
    
    function setUp() public {
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setMoveManager(address(commitManager));
        defaultRegistry = new TestTeamRegistry();
        matchmaker = new DefaultMatchmaker(engine);  // ADD THIS
    }
}
```

### Step 2: Update _startBattle() Calls

**Before:**
```solidity
bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry);
```

**After:**
```solidity
bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker);
```

**With engineHook:**
```solidity
bytes32 battleKey = _startBattle(validator, engine, mockOracle, defaultRegistry, matchmaker, engineHook);
```

## Files That Need Migration

### ✅ Completed
- `test/abstract/BattleHelper.sol` - Updated with new flow

### 🔄 Tests Using BattleHelper (Need matchmaker added to setup)

#### Mon Tests
- [ ] `test/mons/GorillaxTest.sol`
- [ ] `test/mons/EmbursaTest.sol`
- [ ] `test/mons/GhouliathTest.sol`
- [ ] `test/mons/IblivionTest.sol`
- [ ] `test/mons/InutiaTest.sol`
- [ ] `test/mons/MalalienTest.sol`
- [ ] `test/mons/PengymTest.sol`
- [ ] `test/mons/SofabbiTest.sol`
- [ ] `test/mons/VolthareTest.sol`

#### Effect Tests
- [ ] `test/effects/EffectTest.sol`
- [ ] `test/effects/StatBoost.t.sol`

#### Move Tests
- [ ] `test/moves/AttackCalculatorTest.sol`
- [ ] `test/moves/StandardAttackFactoryTest.sol`

### ⚠️ Tests NOT Using BattleHelper (Need manual migration)

These tests call `engine.proposeBattle()`, `engine.acceptBattle()`, and `engine.startBattle()` directly:

- [ ] `test/EngineTest.sol` - Many direct engine calls
- [ ] `test/FastEngineTest.sol` - Many direct engine calls
- [ ] `test/CPUTest.sol` - Special case: CPU accepts battles
- [ ] `test/GachaTeamRegistryTest.sol` - May have battle setup

### ℹ️ Tests That May Not Need Changes
- `test/FastCommitManagerTest.sol`
- `test/GachaTest.sol`
- `test/TeamsTest.sol`

## Key Differences to Remember

1. **Authorization Required**: Both players must authorize the matchmaker before battles can start
   - `engine.authorizeMatchmaker()` is a real function on `Engine.sol`
   - **BattleHelper handles this automatically** - you don't need to call it in tests using `_startBattle()`
   - Tests NOT using BattleHelper must call it manually
2. **ProposedBattle vs Battle**: Use `ProposedBattle` for proposals (has `p0TeamHash`), `Battle` is only used internally
3. **Three-Step Process**: propose → accept → confirm (instead of propose → accept → start)
4. **Integrity Hash**: Now computed via `matchmaker.getBattleProposalIntegrityHash(proposal)`
5. **No Direct Engine Access**: Can't call `engine.proposeBattle/acceptBattle/startBattle` directly anymore

## Special Cases

### CPU Tests
`CPUTest.sol` has logic where the CPU accepts battles. This needs to be updated to:
```solidity
// OLD
cpu.acceptBattle(battleKey, 0, battleIntegrityHash);

// NEW - CPU needs to call matchmaker
matchmaker.acceptBattle(battleKey, 0, battleIntegrityHash);
// (CPU contract may need updates to work with matchmaker)
```

### Tests with Custom Battle Parameters
Tests that customize `ruleset`, `engineHook`, or `moveManager` can use the extended `_startBattle()` overloads:
```solidity
_startBattle(validator, engine, rngOracle, registry, matchmaker, engineHook, ruleset, moveManager)
```

## Testing the Migration

After migrating each file:
1. Run the specific test file: `forge test --match-path test/path/to/TestFile.sol`
2. Check for compilation errors
3. Check for runtime errors related to matchmaker authorization
4. Verify battle keys are computed correctly

## Common Errors

### "MatchmakerNotAuthorized"
- **Cause**: Players haven't authorized the matchmaker
- **Fix**:
  - If using BattleHelper: This shouldn't happen - BattleHelper calls `engine.authorizeMatchmaker()` automatically
  - If NOT using BattleHelper: Manually call `engine.authorizeMatchmaker([address(matchmaker)], [])` for both players

### "BattleNotAccepted"
- **Cause**: Trying to confirm before accepting
- **Fix**: Ensure accept is called before confirm

### "InvalidP0TeamHash"
- **Cause**: Team hash doesn't match the revealed team
- **Fix**: Ensure salt and team index match between proposal and confirmation

