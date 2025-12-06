// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Structs.sol";

import "../abilities/IAbility.sol";
import "../moves/IMoveSet.sol";
import "./IMonRegistry.sol";

interface ITeamRegistry {
    function getMonRegistry() external returns (IMonRegistry);
    function getTeam(address player, uint256 teamIndex) external returns (Mon[] memory);
    function getTeams(address p0, uint256 p0TeamIndex, address p1, uint256 p1TeamIndex) external returns (Mon[] memory, Mon[] memory);
    function getTeamCount(address player) external returns (uint256);
    function getMonRegistryIndicesForTeam(address player, uint256 teamIndex) external returns (uint256[] memory);
}
