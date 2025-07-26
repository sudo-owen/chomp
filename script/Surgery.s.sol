// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Type} from "../src/Enums.sol";

import {IEngine} from "../src/IEngine.sol";
import {MonStats} from "../src/Structs.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

import {IEffect} from "../src/effects/IEffect.sol";
import {DualShock} from "../src/mons/volthare/DualShock.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";

import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        // Edit volthare
        DefaultMonRegistry monRegistry = DefaultMonRegistry(vm.envAddress("DEFAULT_MON_REGISTRY"));
        MonStats memory stats = MonStats({
            hp: 303,
            stamina: 5,
            speed: 311,
            attack: 120,
            defense: 184,
            specialAttack: 255,
            specialDefense: 176,
            type1: Type.Lightning,
            type2: Type.Cyber
        });
        IAbility[] memory emptyAbilities = new IAbility[](0);
        IMoveSet[] memory movesToAdd = new IMoveSet[](1);
        movesToAdd[0] = new DualShock(
            IEngine(vm.envAddress("ENGINE")),
            ITypeCalculator(vm.envAddress("TYPE_CALCULATOR")),
            IEffect(vm.envAddress("ZAP_STATUS"))
        );
        IMoveSet[] memory movesToRemove = new IMoveSet[](1);
        movesToRemove[0] = IMoveSet(0x289bE45F51f052B1bF60E378433156F301BF90c5);
        monRegistry.modifyMon(8, stats, movesToAdd, movesToRemove, emptyAbilities, emptyAbilities);
    }
}
