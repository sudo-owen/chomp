// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Fundamental entities
import {IEffect} from "../src/effects/IEffect.sol";
import {Engine} from "../src/Engine.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";
import {DefaultRuleset} from "../src/DefaultRuleset.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";
import {TypeCalculator} from "../src/types/TypeCalculator.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaRegistry, IGachaRNG} from "../src/gacha/GachaRegistry.sol";
import {GachaTeamRegistry, DefaultTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";

// Important effects
import {StatBoosts} from "../src/effects/StatBoosts.sol";
import {Storm} from "../src/effects/weather/Storm.sol";
import {SleepStatus} from "../src/effects/status/SleepStatus.sol";
import {PanicStatus} from "../src/effects/status/PanicStatus.sol";
import {FrostbiteStatus} from "../src/effects/status/FrostbiteStatus.sol";
import {BurnStatus} from "../src/effects/status/BurnStatus.sol";
import {ZapStatus} from "../src/effects/status/ZapStatus.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract EngineAndPeriphery is Script {
    function run()
        external
        returns (
            DeployData[] memory deployedContracts
        )
    {
        vm.startBroadcast();

        deployedContracts = new DeployData[](17);
    
        Engine engine = new Engine();
        deployedContracts[0] = DeployData({
            name: "ENGINE",
            contractAddress: address(engine)
        });

        FastCommitManager commitManager = new FastCommitManager(engine);
        deployedContracts[1] = DeployData({
            name: "COMMIT MANAGER",
            contractAddress: address(commitManager)
        });

        engine.setCommitManager(address(commitManager));
        TypeCalculator typeCalc = new TypeCalculator();
        deployedContracts[2] = DeployData({
            name: "TYPE CALCULATOR",
            contractAddress: address(typeCalc)
        });

        DefaultMonRegistry monRegistry = new DefaultMonRegistry();
        deployedContracts[3] = DeployData({
            name: "DEFAULT MON REGISTRY",
            contractAddress: address(monRegistry)
        });

        GachaRegistry gachaRegistry = new GachaRegistry(monRegistry, engine, IGachaRNG(address(0)));
        deployedContracts[4] = DeployData({
            name: "GACHA REGISTRY",
            contractAddress: address(gachaRegistry)
        });

        GachaTeamRegistry gachaTeamRegistry = new GachaTeamRegistry(
            DefaultTeamRegistry.Args({
                REGISTRY: gachaRegistry,
                MONS_PER_TEAM: 4,
                MOVES_PER_MON: 4
            }),
            gachaRegistry
        );
        deployedContracts[5] = DeployData({
            name: "GACHA TEAM REGISTRY",
            contractAddress: address(gachaTeamRegistry)
        });

        DefaultRandomnessOracle defaultOracle = new DefaultRandomnessOracle();
        deployedContracts[6] = DeployData({
            name: "DEFAULT RANDOMNESS ORACLE",
            contractAddress: address(defaultOracle)
        });

        DeployData[] memory gameFundamentals = deployGameFundamentals(engine);
        for (uint256 i = 0; i < gameFundamentals.length; i++) {
            deployedContracts[i + 7] = gameFundamentals[i];
        }
        
        vm.stopBroadcast();
    }

    function deployGameFundamentals(Engine engine) public returns (DeployData[] memory deployedContracts) {

        // Deploy game fundamentals
        DeployData[] memory gameFundamentals = new DeployData[](10);

        StaminaRegen staminaRegen = new StaminaRegen(engine);
        gameFundamentals[0] = DeployData({
            name: "STAMINA REGEN",
            contractAddress: address(staminaRegen)
        });

        IEffect[] memory effects = new IEffect[](1);
        effects[0] = staminaRegen;
        DefaultRuleset ruleset = new DefaultRuleset(engine, effects);
        gameFundamentals[1] = DeployData({
            name: "DEFAULT RULESET",
            contractAddress: address(ruleset)
        });

        FastValidator validator = new FastValidator(
            engine, FastValidator.Args({MONS_PER_TEAM: 4, MOVES_PER_MON: 4, TIMEOUT_DURATION: 30})
        );
        gameFundamentals[2] = DeployData({
            name: "FAST VALIDATOR",
            contractAddress: address(validator)
        });

        StatBoosts statBoosts = new StatBoosts(engine);
        gameFundamentals[3] = DeployData({
            name: "STAT BOOSTS",
            contractAddress: address(statBoosts)
        });

        Storm storm = new Storm(engine, statBoosts);
        gameFundamentals[4] = DeployData({
            name: "STORM",
            contractAddress: address(storm)
        });

        SleepStatus sleepStatus = new SleepStatus(engine);
        gameFundamentals[5] = DeployData({
            name: "SLEEP STATUS",
            contractAddress: address(sleepStatus)
        });

        PanicStatus panicStatus = new PanicStatus(engine);
        gameFundamentals[6] = DeployData({
            name: "PANIC STATUS",
            contractAddress: address(panicStatus)
        });

        FrostbiteStatus frostbiteStatus = new FrostbiteStatus(engine, statBoosts);
        gameFundamentals[7] = DeployData({
            name: "FROSTBITE STATUS",
            contractAddress: address(frostbiteStatus)
        });

        BurnStatus burnStatus = new BurnStatus(engine, statBoosts);
        gameFundamentals[8] = DeployData({
            name: "BURN STATUS",
            contractAddress: address(burnStatus)
        });

        ZapStatus zapStatus = new ZapStatus(engine);
        gameFundamentals[9] = DeployData({
            name: "ZAP STATUS",
            contractAddress: address(zapStatus)
        });

        return gameFundamentals;
    }

}