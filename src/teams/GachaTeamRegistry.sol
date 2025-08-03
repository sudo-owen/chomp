// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./LookupTeamRegistry.sol";
import {IOwnableMon} from "../gacha/IOwnableMon.sol";
import {Ownable} from "../lib/Ownable.sol";

contract GachaTeamRegistry is LookupTeamRegistry, Ownable {

    IOwnableMon immutable OWNER_LOOKUP;

    error NotOwner();

    constructor(Args memory args, IOwnableMon _OWNER_LOOKUP) LookupTeamRegistry(args) {
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

    function createTeam(uint256[] memory monIndices) override public {
        _validateOwnership(monIndices);
        super.createTeam(monIndices);
    }

    function createTeamForUser(
        address user,
        uint256[] memory monIndices
    ) external onlyOwner {
        _createTeamForUser(user, monIndices);
    }

    function updateTeamForUser(
        uint256[] memory monIndices
    ) external onlyOwner {
        uint256[] memory teamMonIndicesToOverride = new uint256[](monIndices.length);
        for (uint256 i; i < monIndices.length; i++) {
            teamMonIndicesToOverride[i] = i;
        }
        super.updateTeam(0, monIndices, teamMonIndicesToOverride);
    }

    function updateTeam(
        uint256 teamIndex,
        uint256[] memory teamMonIndicesToOverride,
        uint256[] memory newMonIndices
    ) override public {
        _validateOwnership(newMonIndices);
        super.updateTeam(teamIndex, teamMonIndicesToOverride, newMonIndices);
    }
}