// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IEngine} from "../src/IEngine.sol";
import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";
import {VitalSiphon} from "../src/mons/xmon/VitalSiphon.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {MonStats} from "../src/Structs.sol";
import {Type} from "../src/Enums.sol";
import {IMoveSet} from "../src/moves/IMoveSet.sol";
import {IAbility} from "../src/abilities/IAbility.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        // Deploy new Vital Siphon
        VitalSiphon vitalSiphon = new VitalSiphon(IEngine(vm.envAddress("ENGINE")), ITypeCalculator(vm.envAddress("TYPE_CALCULATOR")));
        deployedContracts.push(DeployData({name: "Vital Siphon", contractAddress: address(vitalSiphon)}));

        // Get the registry and old Vital Siphon address
        DefaultMonRegistry registry = DefaultMonRegistry(vm.envAddress("DEFAULT_MON_REGISTRY"));
        address oldVitalSiphon = vm.envAddress("VITAL_SIPHON");

        // Xmon stats (matching SetupMons.s.sol)
        MonStats memory stats = MonStats({
            hp: 311,
            stamina: 5,
            speed: 285,
            attack: 123,
            defense: 179,
            specialAttack: 222,
            specialDefense: 185,
            type1: Type.Cosmic,
            type2: Type.None
        });

        // Prepare moves to add and remove
        IMoveSet[] memory movesToAdd = new IMoveSet[](1);
        movesToAdd[0] = IMoveSet(address(vitalSiphon));

        IMoveSet[] memory movesToRemove = new IMoveSet[](1);
        movesToRemove[0] = IMoveSet(oldVitalSiphon);

        // No ability changes
        IAbility[] memory abilitiesToAdd = new IAbility[](0);
        IAbility[] memory abilitiesToRemove = new IAbility[](0);

        // Update Xmon (monId 10) registry
        registry.modifyMon(10, stats, movesToAdd, movesToRemove, abilitiesToAdd, abilitiesToRemove);

        vm.stopBroadcast();
        return deployedContracts;
    }
}
