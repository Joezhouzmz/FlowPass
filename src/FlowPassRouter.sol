// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title FlowPassRouter
/// @notice Minimal exact-input ERC20 router that forwards the trader identity to FlowPass hooks.
/// @dev This is intentionally not a general-purpose Uniswap router. It exists so the MVP can
///      demonstrate a realistic PoolManager unlock/swap/settle lifecycle.
contract FlowPassRouter is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public immutable manager;

    struct ExactInputSingleParams {
        PoolKey key;
        bool zeroForOne;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        address recipient;
    }

    struct CallbackData {
        address trader;
        address recipient;
        PoolKey key;
        SwapParams swapParams;
        bytes hookData;
        uint256 amountOutMinimum;
    }

    error InvalidManager();
    error NotPoolManager();
    error ZeroAmountIn();
    error AmountInTooLarge();
    error InsufficientOutputAmount();
    error NativeCurrencyUnsupported();
    error TransferFailed();

    constructor(IPoolManager manager_) {
        if (address(manager_) == address(0)) revert InvalidManager();
        manager = manager_;
    }

    function swapExactInputSingle(ExactInputSingleParams calldata params) external returns (BalanceDelta delta) {
        if (params.amountIn == 0) revert ZeroAmountIn();
        if (params.amountIn > uint256(type(int256).max)) revert AmountInTooLarge();

        address recipient = params.recipient == address(0) ? msg.sender : params.recipient;
        SwapParams memory swapParams = SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: -int256(params.amountIn),
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        bytes memory result = manager.unlock(
            abi.encode(
                CallbackData({
                    trader: msg.sender,
                    recipient: recipient,
                    key: params.key,
                    swapParams: swapParams,
                    hookData: abi.encode(msg.sender),
                    amountOutMinimum: params.amountOutMinimum
                })
            )
        );

        delta = abi.decode(result, (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert NotPoolManager();

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.swapParams, data.hookData);

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        uint256 amountOut = _outputAmount(data.swapParams.zeroForOne, delta);
        if (amountOut < data.amountOutMinimum) revert InsufficientOutputAmount();

        if (amount0 < 0) _settle(data.key.currency0, data.trader, _negatedAmount(amount0));
        if (amount1 < 0) _settle(data.key.currency1, data.trader, _negatedAmount(amount1));
        if (amount0 > 0) manager.take(data.key.currency0, data.recipient, _positiveAmount(amount0));
        if (amount1 > 0) manager.take(data.key.currency1, data.recipient, _positiveAmount(amount1));

        return abi.encode(delta);
    }

    function _outputAmount(bool zeroForOne, BalanceDelta delta) internal pure returns (uint256) {
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        return outputDelta > 0 ? _positiveAmount(outputDelta) : 0;
    }

    function _negatedAmount(int128 amount) internal pure returns (uint256) {
        return uint256(-int256(amount));
    }

    function _positiveAmount(int128 amount) internal pure returns (uint256) {
        return uint256(int256(amount));
    }

    function _settle(Currency currency, address payer, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) revert NativeCurrencyUnsupported();

        manager.sync(currency);
        bool success = IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
        if (!success) revert TransferFailed();
        manager.settle();
    }
}
