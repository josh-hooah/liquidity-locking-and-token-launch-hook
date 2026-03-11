// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {ILaunchManager} from "./interfaces/ILaunchManager.sol";
import {LaunchLockHook} from "./LaunchLockHook.sol";

contract HookDeployer {
    function deploy(bytes32 salt, IPoolManager poolManager, ILaunchManager launchManager) external returns (address hook) {
        hook = address(new LaunchLockHook{salt: salt}(poolManager, launchManager));
    }
}
