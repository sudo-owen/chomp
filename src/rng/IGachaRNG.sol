// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IGachaRNG {
    function getRNG(bytes32 seed, bytes32 battleKey) external view returns (uint256);
}
