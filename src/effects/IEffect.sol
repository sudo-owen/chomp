// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../Enums.sol";
import "../Structs.sol";

interface IEffect {
    // Self explanatory
    function name() external returns (string memory);

    // Whether to run the effect at a specific step
    function shouldRunAtStep(EffectStep r) external returns (bool);

    // Whether or not to add the effect if the step condition is met
    function shouldApply(bytes memory extraData, uint256 targetIndex, uint256 monIndex) external returns (bool);

    // Lifecycle hooks during normal battle flow
    function onRoundStart(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);
    function onRoundEnd(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);

    function onMonSwitchIn(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);

    function onMonSwitchOut(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);

    // NOTE: CURRENTLY ONLY RUN LOCALLY ON MONS (global effects do not have this hook)
    function onAfterDamage(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex, int32 damage)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);

    function onAfterMove(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);

    // Lifecycle hooks when being applied or removed
    function onApply(uint256 rng, bytes memory extraData, uint256 targetIndex, uint256 monIndex)
        external
        returns (bytes memory updatedExtraData, bool removeAfterRun);
    function onRemove(bytes memory extraData, uint256 targetIndex, uint256 monIndex) external;
}
