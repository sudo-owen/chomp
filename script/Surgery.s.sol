// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Script.sol";


import {IEngine} from "../src/IEngine.sol";
import {GachaRegistry, IGachaRNG} from "../src/gacha/GachaRegistry.sol";
import {DefaultMonRegistry} from "../src/teams/DefaultMonRegistry.sol";
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";
import {LookupTeamRegistry} from "../src/teams/LookupTeamRegistry.sol";


struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();
        GachaRegistry gachaRegistry = new GachaRegistry(DefaultMonRegistry(vm.envAddress("DEFAULT_MON_REGISTRY")), IEngine(vm.envAddress("ENGINE")), IGachaRNG(address(0)));
        deployedContracts.push(DeployData({name: "GACHA REGISTRY", contractAddress: address(gachaRegistry)}));
        GachaTeamRegistry gachaTeamRegistry = new GachaTeamRegistry(
            LookupTeamRegistry.Args({REGISTRY: gachaRegistry, MONS_PER_TEAM: 4, MOVES_PER_MON: 4}), gachaRegistry
        );
        deployedContracts.push(DeployData({name: "GACHA TEAM REGISTRY", contractAddress: address(gachaTeamRegistry)}));
        vm.stopBroadcast();

        return deployedContracts;
    }
}
