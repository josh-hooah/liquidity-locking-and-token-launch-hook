// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILiquidityLockVault {
    function deposit(
        bytes32 poolId,
        address from,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 shares);

    function syncUnlockedBps(bytes32 poolId, uint16 unlockedBps) external;

    function withdrawTo(bytes32 poolId, address to, uint256 amount0, uint256 amount1) external;

    function withdrawableAmounts(bytes32 poolId) external view returns (uint256 amount0, uint256 amount1);
}
