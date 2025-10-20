// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";

import "../src/Constants.sol";
import "../src/Enums.sol";
import "../src/Structs.sol";

import {Engine} from "../src/Engine.sol";
import {FastCommitManager} from "../src/FastCommitManager.sol";

contract FastCommitManagerTest is Test {
    FastCommitManager commitManager;
    Engine engine;

    function setUp() public {
        engine = new Engine();
        commitManager = new FastCommitManager(engine);
        engine.setMoveManager(address(commitManager));
    }

    function test_cannotDoubleSet() public {
        vm.expectRevert(Engine.MoveManagerAlreadySet.selector);
        engine.setMoveManager(address(0));
    }

    function test_cannotCommitForArbitraryBattleKey() public {
        vm.expectRevert(FastCommitManager.NotP0OrP1.selector);
        commitManager.commitMove(bytes32(0), "");
    }
}
