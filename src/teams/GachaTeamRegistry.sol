// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DefaultTeamRegistry.sol";
import {IOwnableMon} from "../gacha/IOwnableMon.sol";
import {Ownable} from "../lib/Ownable.sol";

contract GachaTeamRegistry is DefaultTeamRegistry, Ownable {

    IOwnableMon immutable OWNER_LOOKUP;

    error NotOwner();

    constructor(Args memory args, IOwnableMon _OWNER_LOOKUP) DefaultTeamRegistry(args) {
        OWNER_LOOKUP = _OWNER_LOOKUP;
        _initializeOwner(msg.sender);
    }

    function _validateOwnership(uint256[] memory monIndices) internal view {
        for (uint256 i; i < monIndices.length; i++) {
            if (! OWNER_LOOKUP.isOwner(msg.sender, monIndices[i])) {
                revert NotOwner();
            }
        }
    }

    function createTeam(uint256[] memory monIndices, IMoveSet[][] memory moves, IAbility[] memory abilities) override public {
        _validateOwnership(monIndices);
        super.createTeam(monIndices, moves, abilities);
    }

    function createTeamForUser(
        address user,
        uint256[] memory monIndices,
        IMoveSet[][] memory moves,
        IAbility[] memory abilities
    ) external onlyOwner {
        _createTeamForUser(user, monIndices, moves, abilities);
    }

    function updateTeam(
        uint256 teamIndex,
        uint256[] memory teamMonIndicesToOverride,
        uint256[] memory newMonIndices,
        IMoveSet[][] memory newMoves,
        IAbility[] memory newAbilities
    ) override public {
        _validateOwnership(newMonIndices);
        super.updateTeam(teamIndex, teamMonIndicesToOverride, newMonIndices, newMoves, newAbilities);
    }

    function copyTeam(address playerToCopy, uint256 teamIndex) override public {
        // Get team indices of player to copy
        uint256[] memory teamIndices = getMonRegistryIndicesForTeam(playerToCopy, teamIndex);
        _validateOwnership(teamIndices);
        super.copyTeam(playerToCopy, teamIndex);
    }
}