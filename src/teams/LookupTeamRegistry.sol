// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Structs.sol";

import "./IMonRegistry.sol";
import "./ITeamRegistry.sol";

contract LookupTeamRegistry is ITeamRegistry {
    uint32 constant BITS_PER_MON_INDEX = 32;
    uint256 constant ONES_MASK = (2 ** BITS_PER_MON_INDEX) - 1;

    struct Args {
        IMonRegistry REGISTRY;
        uint256 MONS_PER_TEAM;
        uint256 MOVES_PER_MON;
    }

    error InvalidTeamSize();
    error DuplicateMonId();
    error InvalidTeamIndex();

    IMonRegistry immutable REGISTRY;
    uint256 immutable MONS_PER_TEAM;
    uint256 immutable MOVES_PER_MON;

    mapping(address => mapping(uint256 => uint256)) public monRegistryIndicesForTeamPacked;
    mapping(address => uint256) public numTeams;

    constructor(Args memory args) {
        REGISTRY = args.REGISTRY;
        MONS_PER_TEAM = args.MONS_PER_TEAM;
        MOVES_PER_MON = args.MOVES_PER_MON;
    }

    function createTeam(uint256[] memory monIndices) public virtual {
        _createTeamForUser(msg.sender, monIndices);
    }

    function _createTeamForUser(address user, uint256[] memory monIndices) internal {
        if (monIndices.length != MONS_PER_TEAM) {
            revert InvalidTeamSize();
        }

        // Check for duplicate mon indices
        _checkForDuplicates(monIndices);

        // Initialize team and set indices
        uint256 teamId = numTeams[user];
        for (uint256 i; i < MONS_PER_TEAM; i++) {
            _setMonRegistryIndices(teamId, uint32(monIndices[i]), i, user);
        }

        // Update the team index
        numTeams[user] += 1;
    }

    function updateTeam(uint256 teamIndex, uint256[] memory teamMonIndicesToOverride, uint256[] memory newMonIndices)
        public
        virtual
    {
        uint256 numMonsToOverride = teamMonIndicesToOverride.length;

        // Check for duplicate mon indices
        _checkForDuplicates(newMonIndices);

        // Update the team
        for (uint256 i; i < numMonsToOverride; i++) {
            uint256 monIndexToOverride = teamMonIndicesToOverride[i];
            _setMonRegistryIndices(teamIndex, uint32(newMonIndices[i]), monIndexToOverride, msg.sender);
        }
    }

    function _checkForDuplicates(uint256[] memory monIndices) internal view {
        for (uint256 i; i < MONS_PER_TEAM - 1; i++) {
            for (uint256 j = i + 1; j < MONS_PER_TEAM; j++) {
                if (monIndices[i] == monIndices[j]) {
                    revert DuplicateMonId();
                }
            }
        }
    }

    // Layout: | Nothing | Nothing | Mon5 | Mon4 | Mon3 | Mon2 | Mon1 | Mon 0 <-- rightmost bits
    function _setMonRegistryIndices(uint256 teamIndex, uint32 monId, uint256 position, address caller) internal {
        // Create a bitmask to clear the bits we want to modify
        uint256 clearBitmask = ~(ONES_MASK << (position * BITS_PER_MON_INDEX));

        // Get the existing packed value
        uint256 existingPackedValue = monRegistryIndicesForTeamPacked[caller][teamIndex];

        // Clear the bits we want to modify
        uint256 clearedValue = existingPackedValue & clearBitmask;

        // Create the value bitmask with the new monId
        uint256 valueBitmask = uint256(monId) << (position * BITS_PER_MON_INDEX);

        // Combine the cleared value with the new value
        monRegistryIndicesForTeamPacked[caller][teamIndex] = clearedValue | valueBitmask;
    }

    function _getMonRegistryIndex(address player, uint256 teamIndex, uint256 position) internal view returns (uint256) {
        return uint32(monRegistryIndicesForTeamPacked[player][teamIndex] >> (position * BITS_PER_MON_INDEX));
    }

    function getMonRegistryIndicesForTeam(address player, uint256 teamIndex) public view returns (uint256[] memory) {
        if (teamIndex >= numTeams[player]) {
            revert InvalidTeamIndex();
        }
        uint256[] memory ids = new uint256[](MONS_PER_TEAM);
        for (uint256 i; i < MONS_PER_TEAM; ++i) {
            ids[i] = _getMonRegistryIndex(player, teamIndex, i);
        }
        return ids;
    }

    // Read directly from the registry
    function getTeam(address player, uint256 teamIndex) external returns (Mon[] memory) {
        Mon[] memory team = new Mon[](MONS_PER_TEAM);
        for (uint256 i; i < MONS_PER_TEAM; ++i) {
            uint256 monId = _getMonRegistryIndex(player, teamIndex, i);
            (MonStats memory monStats, address[] memory moves, address[] memory abilities) = REGISTRY.getMonData(monId);
            IMoveSet[] memory movesToUse = new IMoveSet[](MOVES_PER_MON);
            for (uint256 j; j < MOVES_PER_MON; ++j) {
                movesToUse[j] = IMoveSet(moves[j]);
            }
            team[i] = Mon({stats: monStats, ability: IAbility(abilities[0]), moves: movesToUse});
        }
        return team;
    }

    function getTeamCount(address player) external view returns (uint256) {
        return numTeams[player];
    }

    function getMonRegistry() external view returns (IMonRegistry) {
        return REGISTRY;
    }
}
