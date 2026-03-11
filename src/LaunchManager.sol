// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {ReasonCodes} from "./libraries/ReasonCodes.sol";
import {UnlockPolicyLibrary} from "./libraries/UnlockPolicyLibrary.sol";
import {ILiquidityLockVault} from "./interfaces/ILiquidityLockVault.sol";

contract LaunchManager is Ownable {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;

    enum UnlockMode {
        TIME,
        VOLUME,
        HYBRID
    }

    enum LaunchStatus {
        ACTIVE,
        PAUSED,
        FINALIZED
    }

    struct LaunchConfig {
        PoolId poolId;
        uint64 launchStartTime;
        uint64 launchEndTime;
        address pairedAsset;
        address creator;
        uint64 policyNonce;
        bool enabled;
    }

    struct UnlockPolicy {
        UnlockMode mode;
        uint64 timeCliffSeconds;
        uint64 timeEpochSeconds;
        uint16 timeUnlockBpsPerEpoch;
        uint256 minTradeSizeForVolume;
        uint256 maxTxAmountInLaunchWindow;
        uint64 cooldownSecondsPerAddress;
        int24 stabilityBandTicks;
        uint64 stabilityMinDurationSeconds;
        bool emergencyPause;
        uint256[] volumeMilestones;
        uint16[] unlockBpsAtMilestone;
    }

    struct LaunchState {
        uint128 totalLiquidityLocked;
        uint16 unlockedBps;
        uint128 cumulativeVolumeToken0;
        uint128 cumulativeVolumeToken1;
        uint64 lastUnlockTimestamp;
        uint64 lastProgressBlock;
        LaunchStatus status;
        int24 referenceTick;
        uint64 stableSinceTimestamp;
    }

    struct Launch {
        LaunchConfig config;
        UnlockPolicy policy;
        LaunchState state;
        address token0;
        address token1;
    }

    struct LaunchConfigParams {
        uint64 launchStartTime;
        uint64 launchEndTime;
        address pairedAsset;
        int24 referenceTick;
    }

    struct UnlockPolicyParams {
        UnlockMode mode;
        uint64 timeCliffSeconds;
        uint64 timeEpochSeconds;
        uint16 timeUnlockBpsPerEpoch;
        uint256 minTradeSizeForVolume;
        uint256 maxTxAmountInLaunchWindow;
        uint64 cooldownSecondsPerAddress;
        int24 stabilityBandTicks;
        uint64 stabilityMinDurationSeconds;
        bool emergencyPause;
        uint256[] volumeMilestones;
        uint16[] unlockBpsAtMilestone;
    }

    error ZeroAddress();
    error NotHook();
    error LaunchNotFound(bytes32 poolId);
    error LaunchExists(bytes32 poolId);
    error InvalidLaunchWindow();
    error NotCreatorOrOwner();
    error LaunchConstraint(bytes32 poolId, uint8 reasonCode);

    event HookSet(address indexed hook);
    event LaunchCreated(bytes32 indexed poolId, address indexed creator, bytes32 configHash);
    event PolicySet(bytes32 indexed poolId, bytes32 policyHash, uint64 policyNonce);
    event LockDeposited(bytes32 indexed poolId, uint256 amount0, uint256 amount1, uint256 liquidityOrShares);
    event UnlockProgressed(bytes32 indexed poolId, uint16 unlockedBps, uint8 reasonCode);
    event LiquidityWithdrawn(bytes32 indexed poolId, address to, uint256 amount0, uint256 amount1, uint256 liquidityOrShares);

    IPoolManager public immutable poolManager;
    ILiquidityLockVault public immutable vault;

    address public launchHook;

    mapping(bytes32 => Launch) private _launches;
    mapping(bytes32 => mapping(address => uint64)) public perAddressLastSwapTime;

    modifier onlyHook() {
        if (msg.sender != launchHook) revert NotHook();
        _;
    }

    constructor(IPoolManager _poolManager, ILiquidityLockVault _vault, address initialOwner) Ownable(initialOwner) {
        if (address(_poolManager) == address(0) || address(_vault) == address(0)) revert ZeroAddress();
        poolManager = _poolManager;
        vault = _vault;
    }

    function setHook(address newHook) external onlyOwner {
        if (newHook == address(0)) revert ZeroAddress();
        launchHook = newHook;
        emit HookSet(newHook);
    }

    function createLaunch(PoolKey calldata key, LaunchConfigParams calldata configParams, UnlockPolicyParams calldata policyParams)
        external
        returns (bytes32 poolId)
    {
        if (launchHook == address(0)) revert ZeroAddress();
        if (address(key.hooks) != launchHook) revert LaunchConstraint(bytes32(0), ReasonCodes.INVALID_POLICY);
        if (configParams.launchStartTime >= configParams.launchEndTime) revert InvalidLaunchWindow();

        PoolId typedPoolId = key.toId();
        poolId = PoolId.unwrap(typedPoolId);

        Launch storage launch = _launches[poolId];
        if (launch.config.enabled) revert LaunchExists(poolId);

        UnlockPolicyLibrary.validate(
            uint8(policyParams.mode),
            policyParams.timeEpochSeconds,
            policyParams.timeUnlockBpsPerEpoch,
            policyParams.volumeMilestones,
            policyParams.unlockBpsAtMilestone
        );

        launch.config = LaunchConfig({
            poolId: typedPoolId,
            launchStartTime: configParams.launchStartTime,
            launchEndTime: configParams.launchEndTime,
            pairedAsset: configParams.pairedAsset,
            creator: msg.sender,
            policyNonce: 1,
            enabled: true
        });

        launch.token0 = Currency.unwrap(key.currency0);
        launch.token1 = Currency.unwrap(key.currency1);

        launch.state.status = policyParams.emergencyPause ? LaunchStatus.PAUSED : LaunchStatus.ACTIVE;
        launch.state.referenceTick = configParams.referenceTick;
        launch.state.stableSinceTimestamp = configParams.launchStartTime;

        _storePolicy(launch.policy, policyParams);

        emit LaunchCreated(poolId, msg.sender, _hashConfig(launch.config));
        emit PolicySet(poolId, _hashPolicy(policyParams), launch.config.policyNonce);
    }

    function setPolicy(bytes32 poolId, UnlockPolicyParams calldata policyParams) external {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        _requireCreatorOrOwner(launch.config.creator);

        UnlockPolicyLibrary.validate(
            uint8(policyParams.mode),
            policyParams.timeEpochSeconds,
            policyParams.timeUnlockBpsPerEpoch,
            policyParams.volumeMilestones,
            policyParams.unlockBpsAtMilestone
        );

        _storePolicy(launch.policy, policyParams);
        launch.config.policyNonce += 1;
        launch.state.status = policyParams.emergencyPause ? LaunchStatus.PAUSED : launch.state.status;

        emit PolicySet(poolId, _hashPolicy(policyParams), launch.config.policyNonce);
    }

    function setEmergencyPause(bytes32 poolId, bool paused) external {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        _requireCreatorOrOwner(launch.config.creator);

        launch.policy.emergencyPause = paused;
        launch.state.status = paused ? LaunchStatus.PAUSED : LaunchStatus.ACTIVE;
    }

    function setReferenceTick(bytes32 poolId, int24 referenceTick) external {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        _requireCreatorOrOwner(launch.config.creator);
        launch.state.referenceTick = referenceTick;
    }

    function depositLockedLiquidity(bytes32 poolId, uint256 amount0, uint256 amount1) external returns (uint256 shares) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        _requireCreatorOrOwner(launch.config.creator);

        shares = vault.deposit(poolId, msg.sender, launch.token0, launch.token1, amount0, amount1);
        launch.state.totalLiquidityLocked += uint128(shares);
        if (launch.state.unlockedBps > 0) {
            vault.syncUnlockedBps(poolId, launch.state.unlockedBps);
        }

        emit LockDeposited(poolId, amount0, amount1, shares);
    }

    function withdrawUnlockedLiquidity(bytes32 poolId, address to, uint256 amount0, uint256 amount1)
        external
        returns (uint256 shares)
    {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        _requireCreatorOrOwner(launch.config.creator);

        vault.withdrawTo(poolId, to, amount0, amount1);
        shares = amount0 + amount1;

        emit LiquidityWithdrawn(poolId, to, amount0, amount1, shares);
    }

    function advance(bytes32 poolId) public returns (uint16 newUnlockedBps) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);

        if (launch.policy.emergencyPause || launch.state.status == LaunchStatus.PAUSED) {
            revert LaunchConstraint(poolId, ReasonCodes.PAUSED);
        }

        (uint16 candidate, bool stabilitySatisfied) = _computeUnlockedBps(poolId, launch, block.timestamp);

        if (!stabilitySatisfied) {
            revert LaunchConstraint(poolId, ReasonCodes.STABILITY_BAND_VIOLATION);
        }

        if (candidate <= launch.state.unlockedBps) {
            return launch.state.unlockedBps;
        }

        launch.state.unlockedBps = candidate;
        launch.state.lastUnlockTimestamp = uint64(block.timestamp);
        launch.state.lastProgressBlock = uint64(block.number);

        if (candidate == 10_000) {
            launch.state.status = LaunchStatus.FINALIZED;
        }

        if (launch.state.totalLiquidityLocked > 0) {
            vault.syncUnlockedBps(poolId, candidate);
        }
        emit UnlockProgressed(poolId, candidate, ReasonCodes.NONE);

        return candidate;
    }

    function onBeforeSwap(PoolKey calldata key, address trader, int256 amountSpecified) external onlyHook {
        bytes32 poolId = PoolId.unwrap(key.toId());
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);

        if (launch.policy.emergencyPause || launch.state.status == LaunchStatus.PAUSED) {
            revert LaunchConstraint(poolId, ReasonCodes.PAUSED);
        }

        if (block.timestamp >= launch.config.launchStartTime && block.timestamp <= launch.config.launchEndTime) {
            uint256 unsignedAmount = _absSigned(amountSpecified);

            if (
                launch.policy.maxTxAmountInLaunchWindow > 0
                    && unsignedAmount > launch.policy.maxTxAmountInLaunchWindow
            ) {
                revert LaunchConstraint(poolId, ReasonCodes.LAUNCH_WINDOW_MAX_TX);
            }

            if (launch.policy.cooldownSecondsPerAddress > 0) {
                uint64 lastSwapAt = perAddressLastSwapTime[poolId][trader];
                if (lastSwapAt != 0 && block.timestamp < lastSwapAt + launch.policy.cooldownSecondsPerAddress) {
                    revert LaunchConstraint(poolId, ReasonCodes.COOLDOWN);
                }
            }
        }
    }

    function onAfterSwap(PoolKey calldata key, address trader, BalanceDelta delta) external onlyHook {
        bytes32 poolId = PoolId.unwrap(key.toId());
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);

        uint256 absAmount0 = _absInt128(delta.amount0());
        uint256 absAmount1 = _absInt128(delta.amount1());

        uint256 tradeScale = absAmount0 > absAmount1 ? absAmount0 : absAmount1;
        if (tradeScale >= launch.policy.minTradeSizeForVolume) {
            launch.state.cumulativeVolumeToken0 += uint128(absAmount0);
            launch.state.cumulativeVolumeToken1 += uint128(absAmount1);
        }

        if (
            launch.policy.cooldownSecondsPerAddress > 0 && block.timestamp >= launch.config.launchStartTime
                && block.timestamp <= launch.config.launchEndTime
        ) {
            perAddressLastSwapTime[poolId][trader] = uint64(block.timestamp);
        }

        if (launch.policy.stabilityBandTicks > 0) {
            (, int24 currentTick,,) = poolManager.getSlot0(PoolId.wrap(poolId));
            if (_withinBand(currentTick, launch.state.referenceTick, launch.policy.stabilityBandTicks)) {
                if (launch.state.stableSinceTimestamp == 0) {
                    launch.state.stableSinceTimestamp = uint64(block.timestamp);
                }
            } else {
                launch.state.stableSinceTimestamp = 0;
            }
        } else if (launch.state.stableSinceTimestamp == 0) {
            launch.state.stableSinceTimestamp = uint64(block.timestamp);
        }
    }

    function previewAdvance(bytes32 poolId) external view returns (uint16 currentUnlockedBps, uint16 candidate, bool stabilitySatisfied)
    {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);

        currentUnlockedBps = launch.state.unlockedBps;
        (candidate, stabilitySatisfied) = _computeUnlockedBps(poolId, launch, block.timestamp);
    }

    function getLaunchConfig(bytes32 poolId) external view returns (LaunchConfig memory) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        return launch.config;
    }

    function getLaunchState(bytes32 poolId) external view returns (LaunchState memory) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        return launch.state;
    }

    function getLaunchPolicy(bytes32 poolId) external view returns (UnlockPolicy memory) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        return launch.policy;
    }

    function getLaunchTokens(bytes32 poolId) external view returns (address token0, address token1) {
        Launch storage launch = _launches[poolId];
        _requireLaunch(launch, poolId);
        return (launch.token0, launch.token1);
    }

    function _storePolicy(UnlockPolicy storage policy, UnlockPolicyParams calldata params) internal {
        policy.mode = params.mode;
        policy.timeCliffSeconds = params.timeCliffSeconds;
        policy.timeEpochSeconds = params.timeEpochSeconds;
        policy.timeUnlockBpsPerEpoch = params.timeUnlockBpsPerEpoch;
        policy.minTradeSizeForVolume = params.minTradeSizeForVolume;
        policy.maxTxAmountInLaunchWindow = params.maxTxAmountInLaunchWindow;
        policy.cooldownSecondsPerAddress = params.cooldownSecondsPerAddress;
        policy.stabilityBandTicks = params.stabilityBandTicks;
        policy.stabilityMinDurationSeconds = params.stabilityMinDurationSeconds;
        policy.emergencyPause = params.emergencyPause;

        delete policy.volumeMilestones;
        delete policy.unlockBpsAtMilestone;

        uint256 len = params.volumeMilestones.length;
        for (uint256 i = 0; i < len; ++i) {
            policy.volumeMilestones.push(params.volumeMilestones[i]);
            policy.unlockBpsAtMilestone.push(params.unlockBpsAtMilestone[i]);
        }
    }

    function _computeUnlockedBps(bytes32 poolId, Launch storage launch, uint256 timestamp)
        internal
        view
        returns (uint16 candidate, bool stabilitySatisfied)
    {
        uint16 timeBps = UnlockPolicyLibrary.computeTimeUnlockBps(
            launch.config.launchStartTime,
            launch.policy.timeCliffSeconds,
            launch.policy.timeEpochSeconds,
            launch.policy.timeUnlockBpsPerEpoch,
            timestamp
        );

        uint256 cumulativeVolume = uint256(launch.state.cumulativeVolumeToken0) + uint256(launch.state.cumulativeVolumeToken1);
        uint16 volumeBps = UnlockPolicyLibrary.computeVolumeUnlockBps(
            cumulativeVolume, launch.policy.volumeMilestones, launch.policy.unlockBpsAtMilestone
        );

        candidate = UnlockPolicyLibrary.combine(uint8(launch.policy.mode), timeBps, volumeBps);
        if (candidate < launch.state.unlockedBps) {
            candidate = launch.state.unlockedBps;
        }

        stabilitySatisfied = _isStabilitySatisfied(poolId, launch, timestamp);
        if (!stabilitySatisfied) {
            candidate = launch.state.unlockedBps;
        }
    }

    function _isStabilitySatisfied(bytes32 poolId, Launch storage launch, uint256 timestamp) internal view returns (bool) {
        if (launch.policy.stabilityBandTicks <= 0 || launch.policy.stabilityMinDurationSeconds == 0) {
            return true;
        }

        if (launch.state.stableSinceTimestamp == 0) {
            return false;
        }

        (, int24 currentTick,,) = poolManager.getSlot0(PoolId.wrap(poolId));
        if (!_withinBand(currentTick, launch.state.referenceTick, launch.policy.stabilityBandTicks)) {
            return false;
        }

        return timestamp >= launch.state.stableSinceTimestamp + launch.policy.stabilityMinDurationSeconds;
    }

    function _withinBand(int24 tick, int24 centerTick, int24 band) internal pure returns (bool) {
        int24 diff = tick - centerTick;
        if (diff < 0) diff = -diff;
        return diff <= band;
    }

    function _requireLaunch(Launch storage launch, bytes32 poolId) internal view {
        if (!launch.config.enabled) revert LaunchNotFound(poolId);
    }

    function _requireCreatorOrOwner(address creator) internal view {
        if (msg.sender != creator && msg.sender != owner()) {
            revert NotCreatorOrOwner();
        }
    }

    function _hashConfig(LaunchConfig memory config) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                config.poolId,
                config.launchStartTime,
                config.launchEndTime,
                config.pairedAsset,
                config.creator,
                config.policyNonce,
                config.enabled
            )
        );
    }

    function _hashPolicy(UnlockPolicyParams calldata policy) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                policy.mode,
                policy.timeCliffSeconds,
                policy.timeEpochSeconds,
                policy.timeUnlockBpsPerEpoch,
                policy.minTradeSizeForVolume,
                policy.maxTxAmountInLaunchWindow,
                policy.cooldownSecondsPerAddress,
                policy.stabilityBandTicks,
                policy.stabilityMinDurationSeconds,
                policy.emergencyPause,
                policy.volumeMilestones,
                policy.unlockBpsAtMilestone
            )
        );
    }

    function _absSigned(int256 value) internal pure returns (uint256) {
        return uint256(value >= 0 ? value : -value);
    }

    function _absInt128(int128 value) internal pure returns (uint256) {
        return uint256(uint128(value >= 0 ? value : -value));
    }
}
