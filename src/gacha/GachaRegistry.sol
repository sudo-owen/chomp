// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../teams/IMonRegistry.sol";
import "../lib/ERC721Soulbound.sol";
import {EnumerableSetLib} from "../lib/EnumerableSetLib.sol";
import {IEngine} from "../IEngine.sol";
import {IEngineHook} from "../IEngineHook.sol";

contract GachaRegistry is IMonRegistry, ERC721Soulbound, IEngineHook {
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

    mapping(address => EnumerableSetLib.Uint256Set) private monsOwned;
    mapping(address => uint256) public pointsBalance;
    mapping(address => uint256) public lastBattleTimestamp;

    error AlreadyFirstRolled();
    error NotYetFirstRolled();
    error NoMoreStock();
    error NotEngine();

    event MonRoll(address indexed player, uint256[] monIds);
    event PointsAwarded(address indexed player, uint256 points);
    event PointsSpent(address indexed player, uint256 points);
    event BonusPoints(bytes32 indexed battleKey);

    constructor(IMonRegistry _MON_REGISTRY, IEngine _ENGINE) ERC721Soulbound("MONS", "MONS") {
        MON_REGISTRY = _MON_REGISTRY;
        ENGINE = _ENGINE;
    }

    function firstRoll() external returns (uint256[] memory monIds) {
        if (balanceOf(msg.sender) > 0) {
            revert AlreadyFirstRolled();
        }
        return _roll(INITIAL_ROLLS);
    }

    function roll(uint256 numRolls) external returns (uint256[] memory monIds) {
        if (balanceOf(msg.sender) == 0) {
            revert NotYetFirstRolled();
        }
        else if (balanceOf(msg.sender) == MON_REGISTRY.getMonCount()) {
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
        bytes32 prng = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender));
        for (uint256 i; i < numRolls; ++i) {
            uint256 monId = uint256(prng) % numMons;
            // Linear probing to solve for duplicate mons
            while (monsOwned[msg.sender].contains(monId)) {
                monId = (monId + 1) % numMons;
            }
            monIds[i] = monId;
            _mint(msg.sender, monId);
            monsOwned[msg.sender].add(monId);
            prng = keccak256(abi.encodePacked(prng));
        }
        emit MonRoll(msg.sender, monIds);
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
        uint256 rng = uint256(blockhash(block.number - 1)) % POINTS_MULTIPLIER_CHANCE_DENOM;
        uint256 pointScale = 1; 
        if (rng == 0) {
            pointScale = POINTS_MULTIPLIER;
            emit BonusPoints(ENGINE.battleKeyForWrite());
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

    // TODO: read from onchain data and compose
    function tokenURI(uint256) public override pure returns (string memory) {
        return "";
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
