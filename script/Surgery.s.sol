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
import {GachaTeamRegistry} from "../src/teams/GachaTeamRegistry.sol";

import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        uint256[] memory monIndices = new uint256[](4);
        monIndices[0] = 5; // Sofabbi
        monIndices[1] = 1; // Inutia
        monIndices[2] = 7; // Embursa
        monIndices[3] = 8; // Volthare

        GachaTeamRegistry gachaTeamRegistry = GachaTeamRegistry(vm.envAddress("GACHA_TEAM_REGISTRY"));
        gachaTeamRegistry.createTeamForUser(0xc610593e78457A103f353b4259233408cb604592, monIndices);

        vm.stopBroadcast();

        return deployedContracts;
    }
}
