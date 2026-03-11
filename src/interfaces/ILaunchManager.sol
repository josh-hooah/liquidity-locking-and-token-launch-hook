// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

interface ILaunchManager {
    function onBeforeSwap(PoolKey calldata key, address trader, int256 amountSpecified) external;

    function onAfterSwap(PoolKey calldata key, address trader, BalanceDelta delta) external;
}
