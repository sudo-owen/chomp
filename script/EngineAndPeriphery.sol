// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Fundamental entities
import {DefaultCommitManager} from "../src/DefaultCommitManager.sol";
import {DefaultRuleset} from "../src/DefaultRuleset.sol";
import {Engine} from "../src/Engine.sol";
import {DefaultValidator} from "../src/DefaultValidator.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";
import {PlayerCPU} from "../src/cpu/PlayerCPU.sol";
import {RandomCPU} from "../src/cpu/RandomCPU.sol";
import {OkayCPU} from "../src/cpu/OkayCPU.sol";
import {IEffect} from "../src/effects/IEffect.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";
import {GachaRegistry, IGachaRNG} from "../src/gacha/GachaRegistry.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ICPURNG} from "../src/rng/ICPURNG.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {LookupTeamRegistry} from "../src/teams/LookupTeamRegistry.sol";
import {TypeCalculator} from "../src/types/TypeCalculator.sol";
import {DefaultMatchmaker} from "../src/matchmaker/DefaultMatchmaker.sol";

// Important effects
import {StatBoosts} from "../src/effects/StatBoosts.sol";
import {BurnStatus} from "../src/effects/status/BurnStatus.sol";
import {FrostbiteStatus} from "../src/effects/status/FrostbiteStatus.sol";
import {PanicStatus} from "../src/effects/status/PanicStatus.sol";
import {SleepStatus} from "../src/effects/status/SleepStatus.sol";
import {ZapStatus} from "../src/effects/status/ZapStatus.sol";
import {Storm} from "../src/effects/weather/Storm.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract EngineAndPeriphery is Script {

    uint256 constant NUM_MONS = 4;
    uint256 constant NUM_MOVES = 4;
    uint256 constant TIMEOUT_DURATION = 60;
    
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        Engine engine = new Engine();
        deployedContracts.push(DeployData({name: "ENGINE", contractAddress: address(engine)}));

        DefaultCommitManager commitManager = new DefaultCommitManager(engine);
        deployedContracts.push(DeployData({name: "COMMIT MANAGER", contractAddress: address(commitManager)}));

        TypeCalculator typeCalc = new TypeCalculator();
        deployedContracts.push(DeployData({name: "TYPE CALCULATOR", contractAddress: address(typeCalc)}));

        DefaultMonRegistry monRegistry = new DefaultMonRegistry();
        deployedContracts.push(DeployData({name: "DEFAULT MON REGISTRY", contractAddress: address(monRegistry)}));

        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, IGachaRNG(address(0)));
        deployedContracts.push(DeployData({name: "GACHA REGISTRY", contractAddress: address(gachaRegistry)}));

        GachaTeamRegistry gachaTeamRegistry = new GachaTeamRegistry(
            LookupTeamRegistry.Args({REGISTRY: gachaRegistry, MONS_PER_TEAM: NUM_MONS, MOVES_PER_MON: NUM_MOVES}), gachaRegistry
        );
        deployedContracts.push(DeployData({name: "GACHA TEAM REGISTRY", contractAddress: address(gachaTeamRegistry)}));

        DefaultRandomnessOracle defaultOracle = new DefaultRandomnessOracle();
        deployedContracts.push(DeployData({name: "DEFAULT RANDOMNESS ORACLE", contractAddress: address(defaultOracle)}));

        RandomCPU cpu = new RandomCPU(NUM_MOVES, engine, ICPURNG(address(0)));
        deployedContracts.push(DeployData({name: "RANDOM CPU", contractAddress: address(cpu)}));

        CPUMoveManager cpuMoveManager = new CPUMoveManager(engine, cpu);
        deployedContracts.push(DeployData({name: "CPU MOVE MANAGER", contractAddress: address(cpuMoveManager)}));

        PlayerCPU playerCPU = new PlayerCPU(NUM_MOVES, engine, ICPURNG(address(0)));
        deployedContracts.push(DeployData({name: "PLAYER CPU", contractAddress: address(playerCPU)}));

        CPUMoveManager playerCPUManager = new CPUMoveManager(engine, playerCPU);
        deployedContracts.push(
            DeployData({name: "PLAYER CPU MOVE MANAGER", contractAddress: address(playerCPUManager)})
        );

        OkayCPU okayCPU = new OkayCPU(NUM_MOVES, engine, ICPURNG(address(0)), typeCalc);
        deployedContracts.push(DeployData({name: "OKAY CPU", contractAddress: address(okayCPU)}));

        CPUMoveManager okayMoveManager = new CPUMoveManager(engine, okayCPU);
        deployedContracts.push(DeployData({name: "OKAY CPU MOVE MANAGER", contractAddress: address(okayMoveManager)}));

        DefaultMatchmaker matchmaker = new DefaultMatchmaker(engine);
        deployedContracts.push(DeployData({name: "DEFAULT MATCHMAKER", contractAddress: address(matchmaker)}));

        deployGameFundamentals(engine);
        vm.stopBroadcast();
        return deployedContracts;
    }

    function deployGameFundamentals(Engine engine) public {
        StaminaRegen staminaRegen = new StaminaRegen(engine);
        deployedContracts.push(DeployData({name: "STAMINA REGEN", contractAddress: address(staminaRegen)}));

        IEffect[] memory effects = new IEffect[](1);
        effects[0] = staminaRegen;
        DefaultRuleset ruleset = new DefaultRuleset(engine, effects);
        deployedContracts.push(DeployData({name: "DEFAULT RULESET", contractAddress: address(ruleset)}));

        DefaultValidator validator =
            new DefaultValidator(engine, DefaultValidator.Args({MONS_PER_TEAM: NUM_MONS, MOVES_PER_MON: NUM_MOVES, TIMEOUT_DURATION: TIMEOUT_DURATION}));
        deployedContracts.push(DeployData({name: "FAST VALIDATOR", contractAddress: address(validator)}));

        StatBoosts statBoosts = new StatBoosts(engine);
        deployedContracts.push(DeployData({name: "STAT BOOSTS", contractAddress: address(statBoosts)}));

        Storm storm = new Storm(engine, statBoosts);
        deployedContracts.push(DeployData({name: "STORM", contractAddress: address(storm)}));

        SleepStatus sleepStatus = new SleepStatus(engine);
        deployedContracts.push(DeployData({name: "SLEEP STATUS", contractAddress: address(sleepStatus)}));

        PanicStatus panicStatus = new PanicStatus(engine);
        deployedContracts.push(DeployData({name: "PANIC STATUS", contractAddress: address(panicStatus)}));

        FrostbiteStatus frostbiteStatus = new FrostbiteStatus(engine, statBoosts);
        deployedContracts.push(DeployData({name: "FROSTBITE STATUS", contractAddress: address(frostbiteStatus)}));

        BurnStatus burnStatus = new BurnStatus(engine, statBoosts);
        deployedContracts.push(DeployData({name: "BURN STATUS", contractAddress: address(burnStatus)}));

        ZapStatus zapStatus = new ZapStatus(engine);
        deployedContracts.push(DeployData({name: "ZAP STATUS", contractAddress: address(zapStatus)}));
    }
}
