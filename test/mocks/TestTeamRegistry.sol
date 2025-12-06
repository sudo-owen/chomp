// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../src/Structs.sol";

import {IMonRegistry} from "../../src/teams/IMonRegistry.sol";
import {ITeamRegistry} from "../../src/teams/ITeamRegistry.sol";

contract TestTeamRegistry is ITeamRegistry {
    mapping(address => Mon[]) public teams;
    uint256[] indices;

    function setTeam(address player, Mon[] memory team) public {
        teams[player] = team;
    }

    function getTeam(address player, uint256) external view returns (Mon[] memory) {
        return teams[player];
    }

    function getTeams(address p0, uint256, address p1, uint256) external view returns (Mon[] memory, Mon[] memory) {
        return (teams[p0], teams[p1]);
    }

    function getTeamCount(address player) external view returns (uint256) {
        return teams[player].length;
    }

    function getMonRegistry() external pure returns (IMonRegistry) {
        return IMonRegistry(address(0));
    }

    function setIndices(uint256[] memory _indices) public {
        indices = _indices;
    }

    function getMonRegistryIndicesForTeam(address, uint256) external view returns (uint256[] memory) {
        return indices;
    }
}
