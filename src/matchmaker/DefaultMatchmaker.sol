// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Battle, ProposedBattle, Mon} from "../Structs.sol";
import {Engine} from "../Engine.sol";
import {IMatchmaker} from "./IMatchmaker.sol";

contract DefaultMatchmaker is IMatchmaker {

    uint96 constant UNSET_P1_TEAM_INDEX = type(uint96).max - 1;

    Engine public immutable ENGINE;

    event BattleProposal(address indexed p0, address indexed p1, bytes32 battleKey);
    event BattleAcceptance(address indexed p1, bytes32 battleKey, uint256 p1TeamIndex);

    error ProposerNotP0();
    error AcceptorNotP1();
    error ConfirmerNotP0();
    error BattleChangedBeforeAcceptance();
    error InvalidP0TeamHash();
    error BattleNotAccepted();

    mapping(bytes32 battleKey => ProposedBattle) private proposals;

    constructor(Engine engine) {
        ENGINE = engine;
    }

    function getBattleProposalIntegrityHash(ProposedBattle memory proposal) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                proposal.p0,
                proposal.p1,
                proposal.p0TeamHash,
                proposal.validator,
                proposal.rngOracle,
                proposal.ruleset,
                proposal.teamRegistry,
                proposal.engineHook,
                proposal.moveManager,
                proposal.matchmaker
            )
        );
    }

    function proposeBattle(ProposedBattle memory proposal) external returns (bytes32 battleKey) {
        if (proposal.p0 != msg.sender) {
            revert ProposerNotP0();
        }
        (battleKey, ) = ENGINE.computeBattleKey(proposal.p0, proposal.p1);
        proposals[battleKey] = proposal;
        proposals[battleKey].p1TeamIndex = UNSET_P1_TEAM_INDEX;
        emit BattleProposal(proposal.p0, proposal.p1, battleKey);
        return battleKey;
    }

    function acceptBattle(bytes32 battleKey, uint96 p1TeamIndex, bytes32 battleIntegrityHash) external {
        ProposedBattle memory proposal = proposals[battleKey];
        if (proposal.p1 == address(0)) {
            proposal.p1 = msg.sender;
        }
        else if (proposal.p1 != msg.sender) {
            revert AcceptorNotP1();
        }
        if (getBattleProposalIntegrityHash(proposal) != battleIntegrityHash) {
            revert BattleChangedBeforeAcceptance();
        }
        proposals[battleKey].p1TeamIndex = p1TeamIndex;
        emit BattleAcceptance(msg.sender, battleKey, p1TeamIndex);
    }

    function confirmBattle(bytes32 battleKey, bytes32 salt, uint96 p0TeamIndex) external {
        ProposedBattle memory proposal = proposals[battleKey];
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
        Mon[][] memory emptyTeams = new Mon[][](2);
        ENGINE.startBattle(Battle({
            p0: proposal.p0,
            p0TeamIndex: p0TeamIndex,
            p1: proposal.p1,
            p1TeamIndex: proposal.p1TeamIndex,
            teamRegistry: proposal.teamRegistry,
            validator: proposal.validator,
            rngOracle: proposal.rngOracle,
            ruleset: proposal.ruleset,
            engineHook: proposal.engineHook,
            moveManager: proposal.moveManager,
            matchmaker: proposal.matchmaker,
            teams: emptyTeams
        }));
    }

    function validateMatch(bytes32 battleKey, address player) external view returns (bool) {
        ProposedBattle memory proposal = proposals[battleKey];
        bool isPlayer = player == proposal.p0 || player == proposal.p1;
        return isPlayer;
    }
}
