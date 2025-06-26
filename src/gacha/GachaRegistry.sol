// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {EnumerableSetLib} from "../lib/EnumerableSetLib.sol";

import "../teams/IMonRegistry.sol";
import {IOwnableMon} from "./IOwnableMon.sol";
import {IEngine} from "../IEngine.sol";
import {IEngineHook} from "../IEngineHook.sol";
import {IGachaRNG} from "../rng/IGachaRNG.sol";

contract GachaRegistry is IMonRegistry, IEngineHook, IOwnableMon {

    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    uint256 constant public INITIAL_ROLLS = 4;
    uint256 constant public ROLL_COST = 300;
    uint256 constant public POINTS_PER_WIN = 50;
    uint256 constant public POINTS_PER_LOSS = 20;
    uint256 constant public POINTS_MULTIPLIER = 3;
    uint256 constant public POINTS_MULTIPLIER_CHANCE_DENOM = 10;
    uint256 constant public BATTLE_COOLDOWN = 23 hours;

    IMonRegistry public immutable MON_REGISTRY;
    IEngine public immutable ENGINE;
    IGachaRNG immutable RNG;

    mapping(address => EnumerableSetLib.Uint256Set) private monsOwned;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public lastBattleTimestamp;

    error AlreadyFirstRolled();
    error NoMoreStock();
    error NotEngine();

    event MonRoll(address indexed player, uint256[] monIds);
    event PointsAwarded(address indexed player, uint256 points);
    event PointsSpent(address indexed player, uint256 points);
    event BonusPoints(bytes32 indexed battleKey);

    constructor(IMonRegistry _MON_REGISTRY, IEngine _ENGINE, IGachaRNG _RNG) {
        MON_REGISTRY = _MON_REGISTRY;
        ENGINE = _ENGINE;
        if (address(_RNG) == address(0)) {
            RNG = IGachaRNG(address(this));
        } else {
            RNG = _RNG;
        }
    }

    // TODO: for testing events in prod, obviously remove this later
    function addPoints(address a, uint256 points) external {
        pointsBalance[a] += points;
    }

    function firstRoll() external returns (uint256[] memory monIds) {
        if (monsOwned[msg.sender].length() > 0) {
            revert AlreadyFirstRolled();
        }
        return _roll(INITIAL_ROLLS);
    }

    function roll(uint256 numRolls) external returns (uint256[] memory monIds) {
        if (monsOwned[msg.sender].length() == MON_REGISTRY.getMonCount()) {
            revert NoMoreStock();
        }
        else {
            pointsBalance[msg.sender] -= numRolls * ROLL_COST;
            emit PointsSpent(msg.sender, numRolls * ROLL_COST);
        }
        return _roll(numRolls);
    }

    function _roll(uint256 numRolls) internal returns (uint256[] memory monIds) {
        monIds = new uint256[](numRolls);
        uint256 numMons = MON_REGISTRY.getMonCount();
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender));
        bytes32 battleKey = ENGINE.battleKeyForWrite();
        uint256 prng = RNG.getRNG(seed, battleKey);
        for (uint256 i; i < numRolls; ++i) {
            uint256 monId = prng % numMons;
            // Linear probing to solve for duplicate mons
            while (monsOwned[msg.sender].contains(monId)) {
                monId = (monId + 1) % numMons;
            }
            monIds[i] = monId;
            monsOwned[msg.sender].add(monId);
            seed = keccak256(abi.encodePacked(seed));
            prng = RNG.getRNG(seed, battleKey);
        }
        emit MonRoll(msg.sender, monIds);
    }

    function getRNG(bytes32 seed, bytes32 battleKey) public view returns (uint256) {
        return uint256(keccak256(abi.encode(blockhash(block.number - 1), seed, ENGINE.getRNG(battleKey, type(uint256).max))));
    }

    // IOwnableMons implementation
    function isOwner(address player, uint256 monId) external view returns (bool) {
        return monsOwned[player].contains(monId);
    }

    function balanceOf(address player) external view returns (uint256) {
        return monsOwned[player].length();
    }

    // IEngineHook implementation
    function onBattleStart(bytes32 battleKey) external override {}

    function onRoundStart(bytes32 battleKey) external override {}

    function onRoundEnd(bytes32 battleKey) external override {}

    function onBattleEnd(bytes32 battleKey) external override {
        if (msg.sender != address(ENGINE)) {
            revert NotEngine();
        }
        address[] memory players = ENGINE.getPlayersForBattle(battleKey);
        address winner = ENGINE.getWinner(battleKey);
        if (winner == address(0)) {
            return;
        }
        uint256 p0Points;
        uint256 p1Points;
        if (winner == players[0]) {
            p0Points = POINTS_PER_WIN;
            p1Points = POINTS_PER_LOSS;
        } else {
            p0Points = POINTS_PER_LOSS;
            p1Points = POINTS_PER_WIN;
        }
        uint256 rng = uint256(RNG.getRNG(battleKey, battleKey)) % POINTS_MULTIPLIER_CHANCE_DENOM;
        uint256 pointScale = 1; 
        if (rng == (POINTS_MULTIPLIER_CHANCE_DENOM - 1)) {
            pointScale = POINTS_MULTIPLIER;
            emit BonusPoints(battleKey);
        }
        if (lastBattleTimestamp[players[0]] + BATTLE_COOLDOWN < block.timestamp) {
            uint256 pointsAwarded = p0Points * pointScale;
            pointsBalance[players[0]] += pointsAwarded;
            lastBattleTimestamp[players[0]] = block.timestamp;
            emit PointsAwarded(players[0], pointsAwarded);
        }
        if (lastBattleTimestamp[players[1]] + BATTLE_COOLDOWN < block.timestamp) {
            uint256 pointsAwarded = p1Points * pointScale;
            pointsBalance[players[1]] += pointsAwarded;
            lastBattleTimestamp[players[1]] = block.timestamp;
            emit PointsAwarded(players[1], pointsAwarded);
        }
    }

    // All IMonRegistry functions are just pass throughs
    function getMonData(uint256 monId)
        external
        returns (MonStats memory mon, address[] memory moves, address[] memory abilities)
    {
        return MON_REGISTRY.getMonData(monId);
    }

    function getMonStats(uint256 monId) external view returns (MonStats memory) {
        return MON_REGISTRY.getMonStats(monId);
    }

    function getMonMetadata(uint256 monId, bytes32 key) external view returns (bytes32) {
        return MON_REGISTRY.getMonMetadata(monId, key);
    }

    function getMonCount() external view returns (uint256) {
        return MON_REGISTRY.getMonCount();
    }

    function getMonIds(uint256 start, uint256 end) external view returns (uint256[] memory) {
        return MON_REGISTRY.getMonIds(start, end);
    }

    function isValidMove(uint256 monId, IMoveSet move) external view returns (bool) {
        return MON_REGISTRY.isValidMove(monId, move);
    }

    function isValidAbility(uint256 monId, IAbility ability) external view returns (bool) {
        return MON_REGISTRY.isValidAbility(monId, ability);
    }

    function validateMon(Mon memory m, uint256 monId) external view returns (bool) {
        return MON_REGISTRY.validateMon(m, monId);
    }
}
