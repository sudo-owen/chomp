// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ProposedBattle} from "../Structs.sol";

interface ICPU {
    function selectMove(bytes32 battleKey, uint256 playerIndex) external returns (uint256 moveIndex, bytes memory extraData);
    function startBattle(ProposedBattle memory proposal) external; 
}
