// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ICPU {
    function selectMove(bytes32 battleKey, uint256 playerIndex) external view returns (uint256 moveIndex, bytes memory extraData);
    function acceptBattle(bytes32 battleKey, uint256 p1TeamIndex, bytes32 battleIntegrityHash) external;
}
