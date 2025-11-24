// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

uint128 constant NO_OP_MOVE_INDEX = type(uint128).max - 1;
uint128 constant SWITCH_MOVE_INDEX = type(uint128).max - 2;

uint256 constant SWITCH_PRIORITY = 6;
uint32 constant DEFAULT_PRIORITY = 3;
uint32 constant DEFAULT_STAMINA = 5;

uint32 constant CRIT_NUM = 3;
uint32 constant CRIT_DENOM = 2;
uint32 constant DEFAULT_CRIT_RATE = 5;

uint32 constant DEFAULT_VOL = 10;
uint32 constant DEFAULT_ACCURACY = 100;

int32 constant CLEARED_MON_STATE_SENTINEL = type(int32).max - 1;
