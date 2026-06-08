// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassHook} from "../../src/FlowPassHook.sol";

contract MockFlowPassRouter {
    FlowPassHook public immutable hook;

    event SwapRouted(address indexed trader, uint24 fee, bool discounted, uint128 consumedUsdVolume);

    constructor(FlowPassHook hook_) {
        hook = hook_;
    }

    function swapExactInput(FlowPassHook.PoolKey calldata key, uint128 requestedUsdVolume, uint128 actualUsdVolume)
        external
        returns (uint24 fee, bool discounted, uint128 consumedUsdVolume)
    {
        (fee, discounted, consumedUsdVolume) =
            hook.recordSwap(key, abi.encode(msg.sender), true, requestedUsdVolume, actualUsdVolume);
        emit SwapRouted(msg.sender, fee, discounted, consumedUsdVolume);
    }

    function swapExactOutput(FlowPassHook.PoolKey calldata key, uint128 requestedUsdVolume, uint128 actualUsdVolume)
        external
        returns (uint24 fee, bool discounted, uint128 consumedUsdVolume)
    {
        (fee, discounted, consumedUsdVolume) =
            hook.recordSwap(key, abi.encode(msg.sender), false, requestedUsdVolume, actualUsdVolume);
        emit SwapRouted(msg.sender, fee, discounted, consumedUsdVolume);
    }
}

