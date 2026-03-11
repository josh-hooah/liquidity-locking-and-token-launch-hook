// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LiquidityLockVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant BPS_DENOMINATOR = 10_000;

    error ZeroAddress();
    error NotManager();
    error InvalidPool();
    error InvalidUnlockBps();
    error UnlockNotMonotonic();
    error NothingToDeposit();
    error WithdrawExceedsUnlocked();

    struct VaultPosition {
        address token0;
        address token1;
        uint128 totalAmount0;
        uint128 totalAmount1;
        uint128 withdrawnAmount0;
        uint128 withdrawnAmount1;
        uint16 unlockedBps;
        bool initialized;
    }

    address public manager;
    mapping(bytes32 => VaultPosition) private _positions;

    event ManagerSet(address indexed manager);
    event Deposited(bytes32 indexed poolId, address indexed from, uint256 amount0, uint256 amount1, uint256 shares);
    event UnlockSynced(bytes32 indexed poolId, uint16 unlockedBps);
    event Withdrawn(bytes32 indexed poolId, address indexed to, uint256 amount0, uint256 amount1);

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert ZeroAddress();
        manager = newManager;
        emit ManagerSet(newManager);
    }

    function deposit(
        bytes32 poolId,
        address from,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external onlyManager nonReentrant returns (uint256 shares) {
        if (poolId == bytes32(0)) revert InvalidPool();
        if (amount0 == 0 && amount1 == 0) revert NothingToDeposit();

        VaultPosition storage position = _positions[poolId];
        if (!position.initialized) {
            position.token0 = token0;
            position.token1 = token1;
            position.initialized = true;
        } else {
            if (position.token0 != token0 || position.token1 != token1) revert InvalidPool();
        }

        if (amount0 > 0) {
            IERC20(token0).safeTransferFrom(from, address(this), amount0);
            position.totalAmount0 += uint128(amount0);
        }

        if (amount1 > 0) {
            IERC20(token1).safeTransferFrom(from, address(this), amount1);
            position.totalAmount1 += uint128(amount1);
        }

        shares = amount0 + amount1;
        emit Deposited(poolId, from, amount0, amount1, shares);
    }

    function syncUnlockedBps(bytes32 poolId, uint16 unlockedBps) external onlyManager {
        if (unlockedBps > BPS_DENOMINATOR) revert InvalidUnlockBps();

        VaultPosition storage position = _positions[poolId];
        if (!position.initialized) revert InvalidPool();
        if (unlockedBps < position.unlockedBps) revert UnlockNotMonotonic();

        position.unlockedBps = unlockedBps;
        emit UnlockSynced(poolId, unlockedBps);
    }

    function withdrawTo(bytes32 poolId, address to, uint256 amount0, uint256 amount1) external onlyManager nonReentrant {
        VaultPosition storage position = _positions[poolId];
        if (!position.initialized) revert InvalidPool();

        (uint256 maxAmount0, uint256 maxAmount1) = withdrawableAmounts(poolId);
        if (amount0 > maxAmount0 || amount1 > maxAmount1) revert WithdrawExceedsUnlocked();

        if (amount0 > 0) {
            position.withdrawnAmount0 += uint128(amount0);
            IERC20(position.token0).safeTransfer(to, amount0);
        }

        if (amount1 > 0) {
            position.withdrawnAmount1 += uint128(amount1);
            IERC20(position.token1).safeTransfer(to, amount1);
        }

        emit Withdrawn(poolId, to, amount0, amount1);
    }

    function withdrawableAmounts(bytes32 poolId) public view returns (uint256 amount0, uint256 amount1) {
        VaultPosition storage position = _positions[poolId];
        if (!position.initialized) {
            return (0, 0);
        }

        uint256 unlocked0 = (uint256(position.totalAmount0) * position.unlockedBps) / BPS_DENOMINATOR;
        uint256 unlocked1 = (uint256(position.totalAmount1) * position.unlockedBps) / BPS_DENOMINATOR;

        amount0 = unlocked0 - uint256(position.withdrawnAmount0);
        amount1 = unlocked1 - uint256(position.withdrawnAmount1);
    }

    function getPosition(bytes32 poolId) external view returns (VaultPosition memory) {
        return _positions[poolId];
    }
}
