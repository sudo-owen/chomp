// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ICPURNG} from "../../src/rng/ICPURNG.sol";

contract MockCPURNG is ICPURNG {
    uint256 rng;

    function setRNG(uint256 a) public {
        rng = a;
    }

    function getRNG(bytes32) external view returns (uint256) {
        return rng;
    }
}
