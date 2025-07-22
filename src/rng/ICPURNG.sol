// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ICPURNG {
    function getRNG(bytes32 seed) external view returns (uint256);
}
