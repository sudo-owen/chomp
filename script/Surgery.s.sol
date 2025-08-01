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
import {EternalGrudge} from "../src/mons/ghouliath/EternalGrudge.sol";
import {RiseFromTheGrave} from "../src/mons/ghouliath/RiseFromTheGrave.sol";
import {StatBoosts} from "../src/effects/StatBoosts.sol";

import {ITypeCalculator} from "../src/types/ITypeCalculator.sol";

struct DeployData {
    string name;
    address contractAddress;
}

contract Surgery is Script {
    DeployData[] deployedContracts;

    function run() external returns (DeployData[] memory) {
        vm.startBroadcast();

        // Edit Ghouliath
        DefaultMonRegistry monRegistry = DefaultMonRegistry(vm.envAddress("DEFAULT_MON_REGISTRY"));
        MonStats memory stats = MonStats({
            hp: 303,
            stamina: 5,
            speed: 181,
            attack: 157,
            defense: 202,
            specialAttack: 151,
            specialDefense: 202,
            type1: Type.Yang,
            type2: Type.Fire
        });        
        IAbility[] memory abilitiesToRemove = new IAbility[](1);
        abilitiesToRemove[0] = IAbility(0xDC70D92642a9D39402B5B3EaC565d977422C085C);
        IAbility[] memory abilitiesToAdd = new IAbility[](1);
        RiseFromTheGrave riseFromTheGrave = new RiseFromTheGrave(IEngine(vm.envAddress("ENGINE")));
        deployedContracts.push(DeployData({
            name: "Rise From The Grave",
            contractAddress: address(riseFromTheGrave)
        }));
        abilitiesToAdd[0] = IAbility(address(riseFromTheGrave));
        IMoveSet[] memory movesToAdd = new IMoveSet[](1);
        EternalGrudge eternalGrudge = new EternalGrudge(IEngine(vm.envAddress("ENGINE")), StatBoosts(vm.envAddress("STAT_BOOSTS")));
        deployedContracts.push(DeployData({
            name: "Eternal Grudge",
            contractAddress: address(eternalGrudge)
        }));
        movesToAdd[0] = IMoveSet(address(eternalGrudge));
        IMoveSet[] memory movesToRemove = new IMoveSet[](1);
        movesToRemove[0] = IMoveSet(0x97C7C7b33247071eE446e8a0BF71eeC56Ee651bD);
        monRegistry.modifyMon(0, stats, movesToAdd, movesToRemove, abilitiesToAdd, abilitiesToRemove);

        vm.stopBroadcast();

        return deployedContracts;
    }
}
