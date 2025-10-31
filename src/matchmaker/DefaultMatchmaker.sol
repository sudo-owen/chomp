// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IEngine} from "../IEngine.sol";
import {ProposedBattle, Battle} from "../Structs.sol";
import {IMatchmaker} from "./IMatchmaker.sol";
import {MappingAllocator} from "../lib/MappingAllocator.sol";

contract DefaultMatchmaker is IMatchmaker, MappingAllocator {

    bytes32 constant public FAST_BATTLE_SENTINAL_HASH = bytes32("FAST_BATTLE_SENTINAL_HASH"); // Used to skip the confirmBattle step
    uint96 constant UNSET_P1_TEAM_INDEX = type(uint96).max - 1; // Used to tell if a battle has been accepted by p1 or not

    IEngine public immutable ENGINE;

    event BattleProposal(bytes32 indexed battleKey, address indexed p0, address indexed p1, bool isFastBattle);
    event BattleAcceptance(bytes32 indexed battleKey, address indexed p1, bytes32 indexed updatedBattleKey);

    error P0P1Same();
    error ProposerNotP0();
    error AcceptorNotP1();
    error ConfirmerNotP0();
    error BattleChangedBeforeAcceptance();
    error InvalidP0TeamHash();
    error BattleNotAccepted();

    mapping(bytes32 battleKey => ProposedBattle) private proposals;
    mapping(bytes32 newBattleKey => bytes32 oldBattleKey) private preP1FillBattleKey;

    constructor(IEngine engine) {
        ENGINE = engine;
    }

    function getBattleProposalIntegrityHash(ProposedBattle memory proposal) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                proposal.p0TeamHash,
                proposal.validator,
                proposal.rngOracle,
                proposal.ruleset,
                proposal.teamRegistry,
                proposal.engineHooks,
                proposal.moveManager,
                proposal.matchmaker
            )
        );
    }

    /*
     P0 can bypass the final acceptBattle call by setting p0TeamIndex in the initial call and bytes32(0) for the p0TeamHash
     In this case, a different event is emitted, and calling acceptBattle will immediately start the battle
    */
    function proposeBattle(ProposedBattle memory proposal) external returns (bytes32 battleKey) {
        if (proposal.p0 != msg.sender) {
            revert ProposerNotP0();
        }
        if (proposal.p0 == proposal.p1) {
            revert P0P1Same();
        }
        (battleKey,) = ENGINE.computeBattleKey(proposal.p0, proposal.p1);
        bytes32 storageKey = _initializeStorageKey(battleKey);
        proposals[storageKey] = proposal;
        proposals[storageKey].p1TeamIndex = UNSET_P1_TEAM_INDEX;
        emit BattleProposal(battleKey, proposal.p0, proposal.p1, proposal.p0TeamHash == FAST_BATTLE_SENTINAL_HASH);
        return battleKey;
    }

    function acceptBattle(bytes32 battleKey, uint96 p1TeamIndex, bytes32 battleIntegrityHash)
        external
        returns (bytes32 updatedBattleKey)
    {
        ProposedBattle storage proposal = proposals[_getStorageKey(battleKey)];
        // Override battle key if p1 is accepting an open battle proposal
        if (proposal.p1 == address(0)) {
            proposal.p1 = msg.sender;
            (bytes32 newBattleKey,) = ENGINE.computeBattleKey(proposal.p0, proposal.p1);
            preP1FillBattleKey[newBattleKey] = battleKey;
            updatedBattleKey = newBattleKey;
        } else if (proposal.p1 != msg.sender) {
            revert AcceptorNotP1();
        }
        if (getBattleProposalIntegrityHash(proposal) != battleIntegrityHash) {
            revert BattleChangedBeforeAcceptance();
        }
        proposal.p1TeamIndex = p1TeamIndex;
        if (proposal.p0TeamHash == FAST_BATTLE_SENTINAL_HASH) {
            ENGINE.startBattle(
                Battle({
                    p0: proposal.p0,
                    p0TeamIndex: proposal.p0TeamIndex,
                    p1: proposal.p1,
                    p1TeamIndex: proposal.p1TeamIndex,
                    teamRegistry: proposal.teamRegistry,
                    validator: proposal.validator,
                    rngOracle: proposal.rngOracle,
                    ruleset: proposal.ruleset,
                    engineHooks: proposal.engineHooks,
                    moveManager: proposal.moveManager,
                    matchmaker: proposal.matchmaker
                })
            );
            _cleanUpBattleProposal(battleKey);
        }
        else {
            emit BattleAcceptance(battleKey, msg.sender, updatedBattleKey);
        }
    }

    function confirmBattle(bytes32 battleKey, bytes32 salt, uint96 p0TeamIndex) external {
        bytes32 battleKeyToUse = battleKey;
        bytes32 battleKeyOverride = preP1FillBattleKey[battleKey];
        if (battleKeyOverride != bytes32(0)) {
            battleKeyToUse = battleKeyOverride;
        }
        ProposedBattle storage proposal = proposals[_getStorageKey(battleKeyToUse)];
        if (proposal.p1TeamIndex == UNSET_P1_TEAM_INDEX) {
            revert BattleNotAccepted();
        }
        if (proposal.p0 != msg.sender) {
            revert ConfirmerNotP0();
        }
        uint256[] memory p0TeamIndices = proposal.teamRegistry.getMonRegistryIndicesForTeam(msg.sender, p0TeamIndex);
        bytes32 revealedP0TeamHash = keccak256(abi.encodePacked(salt, p0TeamIndex, p0TeamIndices));
        if (revealedP0TeamHash != proposal.p0TeamHash) {
            revert InvalidP0TeamHash();
        }
        ENGINE.startBattle(
            Battle({
                p0: proposal.p0,
                p0TeamIndex: p0TeamIndex,
                p1: proposal.p1,
                p1TeamIndex: proposal.p1TeamIndex,
                teamRegistry: proposal.teamRegistry,
                validator: proposal.validator,
                rngOracle: proposal.rngOracle,
                ruleset: proposal.ruleset,
                engineHooks: proposal.engineHooks,
                moveManager: proposal.moveManager,
                matchmaker: proposal.matchmaker
            })
        );
        _cleanUpBattleProposal(battleKey);
    }

    function _cleanUpBattleProposal(bytes32 battleKey) internal {
        _freeStorageKey(battleKey);
        delete preP1FillBattleKey[battleKey];
    }

    function validateMatch(bytes32 battleKey, address player) external view returns (bool) {
        bytes32 battleKeyToUse = battleKey;
        bytes32 battleKeyOverride = preP1FillBattleKey[battleKey];
        if (battleKeyOverride != bytes32(0)) {
            battleKeyToUse = battleKeyOverride;
        }
        ProposedBattle storage proposal = proposals[_getStorageKey(battleKeyToUse)];
        bool isPlayer = player == proposal.p0 || player == proposal.p1;
        return isPlayer;
    }
}
