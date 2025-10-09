/**
 * - On swap in, check if storm is already applied globally
 * - If so, adjust its duration to be 3 (never more than 3)
 * - Storm is a global effect:
 *  - When applied, boosts friendly team's speed, decreases friendly team's sp def
 *  - On friendly mon swap in, does the same thing
 *  - These boosts use the normal stat boost (which clears automatically on switch)
 *  - On clear, reset all stat boosts on mons still in
 */

// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import {IEngine} from "../../IEngine.sol";
import {IAbility} from "../../abilities/IAbility.sol";
import {Storm} from "../../effects/weather/Storm.sol";

contract Overclock is IAbility {
    IEngine immutable ENGINE;
    Storm immutable STORM;

    constructor(IEngine _ENGINE, Storm _STORM) {
        ENGINE = _ENGINE;
        STORM = _STORM;
    }

    function name() public pure override returns (string memory) {
        return "Overclock";
    }

    function activateOnSwitch(bytes32, uint256 playerIndex, uint256) external override {
        STORM.applyStorm(playerIndex);
    }
}
