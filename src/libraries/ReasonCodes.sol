// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ReasonCodes {
    uint8 internal constant NONE = 0;
    uint8 internal constant LAUNCH_WINDOW_MAX_TX = 1;
    uint8 internal constant COOLDOWN = 2;
    uint8 internal constant NOT_ALLOWLISTED = 3;
    uint8 internal constant STABILITY_BAND_VIOLATION = 4;
    uint8 internal constant NOT_YET_UNLOCKED = 5;
    uint8 internal constant PAUSED = 6;
    uint8 internal constant INVALID_POLICY = 7;
}
