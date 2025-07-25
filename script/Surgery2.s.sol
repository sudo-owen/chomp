// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {DefaultRuleset} from "../src/DefaultRuleset.sol";
import {Engine} from "../src/Engine.sol";

import {Type} from "../src/Enums.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";
import {FastValidator} from "../src/FastValidator.sol";
import {IEngine} from "../src/IEngine.sol";

import {MonStats} from "../src/Structs.sol";
import {IAbility} from "../src/abilities/IAbility.sol";
import {CPUMoveManager} from "../src/cpu/CPUMoveManager.sol";
import {RandomCPU} from "../src/cpu/RandomCPU.sol";
import {IEffect} from "../src/effects/IEffect.sol";
import {StaminaRegen} from "../src/effects/StaminaRegen.sol";
import {GachaRegistry, IGachaRNG} from "../src/gacha/GachaRegistry.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";

import {DefaultRandomnessOracle} from "../src/rng/DefaultRandomnessOracle.sol";
import {ICPURNG} from "../src/rng/ICPURNG.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";

import {DefaultTeamRegistry, GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {TypeCalculator} from "../src/types/TypeCalculator.sol";

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

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();
        StaminaRegen staminaRegen = new StaminaRegen(IEngine(vm.envAddress("ENGINE")));
        deployedContracts.push(DeployData({name: "STAMINA REGEN", contractAddress: address(staminaRegen)}));
        IEffect[] memory effects = new IEffect[](1);
        effects[0] = IEffect(address(staminaRegen));
        deployedContracts.push(
            DeployData({
                name: "DEFAULT RULESET",
                contractAddress: address(new DefaultRuleset(IEngine(vm.envAddress("ENGINE")), effects))
            })
        );
        return deployedContracts;
    }
}
