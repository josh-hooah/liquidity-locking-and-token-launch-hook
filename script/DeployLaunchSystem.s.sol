// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {LaunchManager} from "../src/LaunchManager.sol";
import {LaunchLockHook} from "../src/LaunchLockHook.sol";
import {LiquidityLockVault} from "../src/LiquidityLockVault.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {ILiquidityLockVault} from "../src/interfaces/ILiquidityLockVault.sol";
import {ILaunchManager} from "../src/interfaces/ILaunchManager.sol";

contract DeployLaunchSystem is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        address configuredPoolManager = vm.envOr("POOL_MANAGER_ADDRESS", address(0));

        vm.startBroadcast(deployerPk);

        IPoolManager poolManager;
        bool deployedPoolManager = configuredPoolManager == address(0);
        if (deployedPoolManager) {
            poolManager = IPoolManager(address(new PoolManager(owner)));
        } else {
            poolManager = IPoolManager(configuredPoolManager);
        }

        LiquidityLockVault vault = new LiquidityLockVault(owner);
        LaunchManager launchManager = new LaunchManager(poolManager, ILiquidityLockVault(address(vault)), owner);
        HookDeployer hookDeployer = new HookDeployer();

        vault.setManager(address(launchManager));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        (address expectedAddress, bytes32 salt) = HookMiner.find(
            address(hookDeployer),
            flags,
            type(LaunchLockHook).creationCode,
            abi.encode(IPoolManager(address(poolManager)), ILaunchManager(address(launchManager)))
        );

        LaunchLockHook hook = LaunchLockHook(
            hookDeployer.deploy(salt, poolManager, ILaunchManager(address(launchManager)))
        );

        require(address(hook) == expectedAddress, "hook mismatch");
        launchManager.setHook(address(hook));

        vm.stopBroadcast();

        console2.log("DEPLOYER", deployer);
        console2.log("OWNER", owner);
        if (deployedPoolManager) {
            console2.log("POOL_MANAGER", address(poolManager));
        } else {
            console2.log("POOL_MANAGER_REUSED", address(poolManager));
        }
        console2.log("VAULT", address(vault));
        console2.log("LAUNCH_MANAGER", address(launchManager));
        console2.log("HOOK_DEPLOYER", address(hookDeployer));
        console2.log("HOOK", address(hook));
    }
}
