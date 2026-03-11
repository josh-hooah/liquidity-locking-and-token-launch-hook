// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library UnlockPolicyLibrary {
    uint16 internal constant BPS_DENOMINATOR = 10_000;

    error InvalidPolicy();

    function validate(
        uint8 mode,
        uint64 timeEpochSeconds,
        uint16 timeUnlockBpsPerEpoch,
        uint256[] calldata volumeMilestones,
        uint16[] calldata unlockBpsAtMilestone
    ) internal pure {
        if (mode > 2) revert InvalidPolicy();

        bool usesTime = mode == 0 || mode == 2;
        bool usesVolume = mode == 1 || mode == 2;

        if (usesTime) {
            if (timeEpochSeconds == 0 || timeUnlockBpsPerEpoch == 0) revert InvalidPolicy();
        }

        if (usesVolume) {
            uint256 len = volumeMilestones.length;
            if (len == 0 || len != unlockBpsAtMilestone.length) revert InvalidPolicy();

            uint256 prevMilestone;
            uint16 prevBps;
            for (uint256 i = 0; i < len; ++i) {
                uint256 milestone = volumeMilestones[i];
                uint16 bps = unlockBpsAtMilestone[i];

                if (milestone == 0 || bps == 0 || bps > BPS_DENOMINATOR) revert InvalidPolicy();
                if (i > 0) {
                    if (milestone <= prevMilestone) revert InvalidPolicy();
                    if (bps < prevBps) revert InvalidPolicy();
                }
                prevMilestone = milestone;
                prevBps = bps;
            }
        }
    }

    function computeTimeUnlockBps(
        uint256 launchStartTime,
        uint256 timeCliffSeconds,
        uint256 timeEpochSeconds,
        uint16 timeUnlockBpsPerEpoch,
        uint256 timestamp
    ) internal pure returns (uint16) {
        if (timestamp < launchStartTime + timeCliffSeconds) {
            return 0;
        }

        if (timeEpochSeconds == 0 || timeUnlockBpsPerEpoch == 0) {
            return 0;
        }

        uint256 elapsedAfterCliff = timestamp - (launchStartTime + timeCliffSeconds);
        uint256 epochs = (elapsedAfterCliff / timeEpochSeconds) + 1;
        uint256 rawBps = epochs * uint256(timeUnlockBpsPerEpoch);

        return rawBps >= BPS_DENOMINATOR ? BPS_DENOMINATOR : uint16(rawBps);
    }

    function computeVolumeUnlockBps(
        uint256 cumulativeVolume,
        uint256[] storage volumeMilestones,
        uint16[] storage unlockBpsAtMilestone
    ) internal view returns (uint16 bps) {
        uint256 len = volumeMilestones.length;
        for (uint256 i = 0; i < len; ++i) {
            if (cumulativeVolume < volumeMilestones[i]) break;
            bps = unlockBpsAtMilestone[i];
        }
    }

    function combine(uint8 mode, uint16 timeBps, uint16 volumeBps) internal pure returns (uint16) {
        if (mode == 0) return timeBps;
        if (mode == 1) return volumeBps;

        return timeBps <= volumeBps ? timeBps : volumeBps;
    }
}
