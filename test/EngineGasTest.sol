// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {DefaultRuleset} from "../src/DefaultRuleset.sol";

import {DefaultCommitManager} from "../src/DefaultCommitManager.sol";
import {Engine} from "../src/Engine.sol";
import {IEngine} from "../src/IEngine.sol";
import {DefaultValidator} from "../src/DefaultValidator.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

import {IEffect} from "../src/effects/IEffect.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";

import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {CustomAttack} from "./mocks/CustomAttack.sol";

import {AfterDamageReboundEffect} from "./mocks/AfterDamageReboundEffect.sol";
import {EffectAbility} from "./mocks/EffectAbility.sol";
import {EffectAttack} from "./mocks/EffectAttack.sol";
import {ForceSwitchMove} from "./mocks/ForceSwitchMove.sol";
import {GlobalEffectAttack} from "./mocks/GlobalEffectAttack.sol";
import {InstantDeathEffect} from "./mocks/InstantDeathEffect.sol";
import {InstantDeathOnSwitchInEffect} from "./mocks/InstantDeathOnSwitchInEffect.sol";
import {SelfSwitchAndDamageMove} from "./mocks/SelfSwitchAndDamageMove.sol";
import {InvalidMove} from "./mocks/InvalidMove.sol";
import {MockRandomnessOracle} from "./mocks/MockRandomnessOracle.sol";
import {StatBoostsMove} from "./mocks/StatBoostsMove.sol";

import {BurnStatus} from "../src/effects/status/BurnStatus.sol";
import {FrostbiteStatus} from "../src/effects/status/FrostbiteStatus.sol";
import {StatBoosts} from "../src/effects/StatBoosts.sol";

import {IEngineHook} from "../src/IEngineHook.sol";

import {OneTurnStatBoost} from "./mocks/OneTurnStatBoost.sol";
import {SingleInstanceEffect} from "./mocks/SingleInstanceEffect.sol";
import {SkipTurnMove} from "./mocks/SkipTurnMove.sol";
import {TempStatBoostEffect} from "./mocks/TempStatBoostEffect.sol";
import {TestTeamRegistry} from "./mocks/TestTeamRegistry.sol";

import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";
import {BattleHelper} from "./abstract/BattleHelper.sol";
import {TestTypeCalculator} from "./mocks/TestTypeCalculator.sol";

contract EngineGasTest is Test, BattleHelper {

    DefaultCommitManager commitManager;
    Engine engine;
    ITypeCalculator typeCalc;
    DefaultRandomnessOracle defaultOracle;
    TestTeamRegistry defaultRegistry;
    DefaultMatchmaker matchmaker;

    function setUp() public {
        defaultOracle = new DefaultRandomnessOracle();
        engine = new Engine();
        commitManager = new DefaultCommitManager(engine);
        typeCalc = new TestTypeCalculator();
        defaultRegistry = new TestTeamRegistry();
        matchmaker = new DefaultMatchmaker(engine);
    }

    /**
        - Two teams of 4 mons
        - Each mon has 4 moves:
            - burn move
            - frostbite move
            - stat boost move
            - attacking move
        - Set up with default stamina regen
        - Battle 2:
            - Both players send in mon 0
            - Alice sets up self-stat boost, Bob sets up Burn
            - Alice KOs Bob
            - Bob swaps in mon index 1
            - Alice swaps in mon index 1, Bob sets up Frostbite
            - Alice sets up self-stat boost, Bob rests
            - Alice KOs Bob
            - Bob sends in mon index 2
            - Alice rests, Bob uses self-stat boost
            - Alice rests, Bob KOs
            - Alice uses self-stat boost, Bob uses self-stat boost
            - Alice KOs, Bob rests
            - Bob sends in mon index 3
            - Alice KOs, Bob rests
     */

     function test_consecutiveBattleGas() public {
        Mon memory mon = _createMon();
        mon.stats.stamina = 5;
        mon.stats.attack = 10;
        mon.stats.specialAttack = 10;

        mon.moves = new IMoveSet[](4);
        StatBoosts statBoosts = new StatBoosts(engine);
        IMoveSet burnMove = new EffectAttack(engine, new BurnStatus(engine, statBoosts), EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet frostbiteMove = new EffectAttack(engine, new FrostbiteStatus(engine, statBoosts), EffectAttack.Args({TYPE: Type.Fire, STAMINA_COST: 1, PRIORITY: 1}));
        IMoveSet statBoostMove = new StatBoostsMove(engine, statBoosts);
        IMoveSet damageMove = new CustomAttack(engine, ITypeCalculator(address(typeCalc)), CustomAttack.Args({TYPE: Type.Fire, BASE_POWER: 10, ACCURACY: 100, STAMINA_COST: 1, PRIORITY: 1}));
        mon.moves[0] = burnMove;
        mon.moves[1] = frostbiteMove;
        mon.moves[2] = statBoostMove;
        mon.moves[3] = damageMove;

        Mon[] memory team = new Mon[](4);
        for (uint256 i = 0; i < team.length; i++) {
            team[i] = mon;
        }
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        DefaultValidator validator = new DefaultValidator(
            IEngine(address(engine)), DefaultValidator.Args({MONS_PER_TEAM: team.length, MOVES_PER_MON: mon.moves.length, TIMEOUT_DURATION: 10})
        );
        StaminaRegen staminaRegen = new StaminaRegen(engine);
        IEffect[] memory effects = new IEffect[](1);
        effects[0] = staminaRegen;
        DefaultRuleset ruleset = new DefaultRuleset(IEngine(address(engine)), effects);

        vm.startSnapshotGas("Setup 1");
        bytes32 battleKey =  _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, new IEngineHook[](0), IRuleset(address(ruleset)), address(commitManager));
        uint256 setup1Gas = vm.stopSnapshotGas("Setup 1");

        // - Battle 1:
        // - Both players send in mon 0 [x]
        // - Alice sets up Burn, Bob sets up Frostbite [x]
        // - Alice swaps to mon 1, Bob sets up self-stat boost [x]
        // - Alice sets up self-stat boost, Bob KOs [x]
        // - Alice swaps in mon index 0 
        // - Alice sets up self-stat boost, Bob rests
        // - Alice KOs Bob
        // - Bob sends in mon index 1
        // - Alice rests, Bob uses self-stat boost
        // - Alice rests, Bob KOs
        // - Alice swaps in mon index 2
        // - Alice rests, Bob KOs
        // - Alice swaps in mon index 3
        // - Alice rests, Bob KOs
        vm.startSnapshotGas("FirstBattle");
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0));
        // Alice uses burn, Bob uses frostbite
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 0, 1, "", "");
        // Bob is mon index 0, we boost attack by 90%
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, SWITCH_MOVE_INDEX, 2, abi.encode(1), abi.encode(1, 0, uint256(MonStateIndexName.Attack), int32(90)));
        // Alice is now mon index 1, Bob is mon index 0
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 2, 3, abi.encode(0, 1, uint256(MonStateIndexName.Attack), int32(90)), "");
        // Alice swaps in mon index 0
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(0), true);
        // Alice is now mon index 0, Bob rests
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 2, NO_OP_MOVE_INDEX, abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(90)), "");
        // Alice KOs Bob
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, 3, NO_OP_MOVE_INDEX, "", "");
        // Bob sends in mon index 1
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(1), true);
        // Alice rests, Bob uses self-stat boost
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 2, "", abi.encode(1, 1, uint256(MonStateIndexName.Attack), int32(90)));
        // Alice rests, Bob KOs
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 3, "", "");
        // Alice swaps in mon index 2
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(2), true);
        // Alice rests, Bob KOs
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 3, "", "");
        // Alice swaps in mon index 3
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey, SWITCH_MOVE_INDEX, "", abi.encode(3), true);
        // Alice rests, Bob KOs
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey, NO_OP_MOVE_INDEX, 3, "", "");
        uint256 firstBattleGas = vm.stopSnapshotGas("FirstBattle");

        vm.startSnapshotGas("Intermediary stuff");
        // Rearrange order of moves for battle 2
        mon.moves[1] = burnMove;
        mon.moves[2] = frostbiteMove;
        mon.moves[3] = statBoostMove;
        mon.moves[0] = damageMove;
        for (uint256 i = 0; i < team.length; i++) {
            team[i] = mon;
        }
        defaultRegistry.setTeam(ALICE, team);
        defaultRegistry.setTeam(BOB, team);
        vm.stopSnapshotGas("Intermediary stuff");

        // - Battle 2:
        //     - Both players send in mon 0
        //     - Alice sets up self-stat boost, Bob sets up Burn
        //     - Alice KOs Bob
        //     - Bob swaps in mon index 1
        //     - Alice swaps in mon index 1, Bob sets up Frostbite
        //     - Alice sets up self-stat boost, Bob rests
        //     - Alice KOs Bob
        //     - Bob sends in mon index 2
        //     - Alice rests, Bob uses self-stat boost
        //     - Alice rests, Bob KOs
        //     - Alice swaps in mon index 2
        //     - Alice uses self-stat boost, Bob uses self-stat boost
        //     - Alice KOs, Bob rests
        //     - Bob sends in mon index 3
        //     - Alice KOs, Bob rests
        vm.startSnapshotGas("Setup 2");
        bytes32 battleKey2 =  _startBattle(validator, engine, defaultOracle, defaultRegistry, matchmaker, new IEngineHook[](0), IRuleset(address(ruleset)), address(commitManager));
        uint256 setup2Gas = vm.stopSnapshotGas("Setup 2");

        // - Both players send in mon 0
        vm.startSnapshotGas("SecondBattle");
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, SWITCH_MOVE_INDEX, SWITCH_MOVE_INDEX, abi.encode(0), abi.encode(0));
        // - Alice sets up self-stat boost (move 3), Bob sets up Burn (move 1)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 3, 1, abi.encode(0, 0, uint256(MonStateIndexName.Attack), int32(90)), "");
        // - Alice KOs Bob (move 0 = damage)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 0, NO_OP_MOVE_INDEX, "", "");
        // - Bob swaps in mon index 1
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey2, SWITCH_MOVE_INDEX, "", abi.encode(1), true);
        // - Alice swaps in mon index 1, Bob sets up Frostbite (move 2)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, SWITCH_MOVE_INDEX, 2, abi.encode(1), "");
        // - Alice sets up self-stat boost (move 3, playerIndex=0, monIndex=1), Bob rests
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 3, NO_OP_MOVE_INDEX, abi.encode(0, 1, uint256(MonStateIndexName.Attack), int32(90)), "");
        // - Alice KOs Bob (move 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 0, NO_OP_MOVE_INDEX, "", "");
        // - Bob sends in mon index 2
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey2, SWITCH_MOVE_INDEX, "", abi.encode(2), true);
        // - Alice rests, Bob uses self-stat boost (move 3, playerIndex=1, monIndex=2)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, NO_OP_MOVE_INDEX, 3, "", abi.encode(1, 2, uint256(MonStateIndexName.Attack), int32(90)));
        // - Alice rests, Bob KOs (move 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, NO_OP_MOVE_INDEX, 0, "", "");
        // - Alice swaps in mon index 2
        vm.startPrank(ALICE);
        commitManager.revealMove(battleKey2, SWITCH_MOVE_INDEX, "", abi.encode(2), true);
        // - Alice uses self-stat boost (move 3, p0 mon2), Bob uses self-stat boost (move 3, p1 mon2)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 3, 3, abi.encode(0, 2, uint256(MonStateIndexName.Attack), int32(90)), abi.encode(1, 2, uint256(MonStateIndexName.Attack), int32(90)));
        // - Alice KOs Bob (move 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 0, NO_OP_MOVE_INDEX, "", "");
        // - Bob sends in mon index 3
        vm.startPrank(BOB);
        commitManager.revealMove(battleKey2, SWITCH_MOVE_INDEX, "", abi.encode(3), true);
        // - Alice KOs Bob (move 0)
        _commitRevealExecuteForAliceAndBob(engine, commitManager, battleKey2, 0, NO_OP_MOVE_INDEX, "", "");
        uint256 secondBattleGas = vm.stopSnapshotGas("SecondBattle");

        // Setup comparison
        assertLt(setup2Gas, setup1Gas);

        // Battle comparison
        // assertLt(secondBattleGas, firstBattleGas);
     }
}