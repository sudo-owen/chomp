// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Structs.sol";
import "./effects/IEffect.sol";

interface IRuleset {
    // Returns which global effects to start the game with
    function getInitialGlobalEffects() external returns (IEffect[] memory, bytes32[] memory);
}
