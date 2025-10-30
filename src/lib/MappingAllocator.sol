// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

abstract contract MappingAllocator {

    bytes32[] private freeStorageKeys;
    mapping(bytes32 => bytes32) private battleKeyToStorageKey;

    function _initializeStorageKey(bytes32 key) internal returns (bytes32) {
        uint256 numFreeKeys = freeStorageKeys.length;
        if (numFreeKeys == 0) {
            return key;
        }
        else {
            bytes32 freeKey = freeStorageKeys[numFreeKeys - 1];
            freeStorageKeys.pop();
            battleKeyToStorageKey[key] = freeKey;
            return freeKey;
        }
    }

    function _getStorageKey(bytes32 battleKey) internal view returns (bytes32) {
        bytes32 storageKey = battleKeyToStorageKey[battleKey];
        if (storageKey == bytes32(0)) {
            return battleKey;
        }
        else {
            return storageKey;
        }
    }

    function _freeStorageKey(bytes32 battleKey) internal {
        bytes32 storageKey = _getStorageKey(battleKey);
        freeStorageKeys.push(storageKey);
        delete battleKeyToStorageKey[battleKey];
    }
}
