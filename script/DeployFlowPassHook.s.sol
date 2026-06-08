// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassHook, IERC20} from "../src/FlowPassHook.sol";

/// @notice Minimal local deploy helper that does not depend on forge-std.
/// @dev For real broadcast deployment, this can be replaced with a forge-std Script contract.
contract DeployFlowPassHook {
    uint256 public constant PASS_PRICE = 300e6;
    uint128 public constant QUOTA_USD_VOLUME = 10_000_000e6;
    uint64 public constant DURATION = 7 days;
    uint24 public constant DISCOUNT_FEE = 50;
    uint16 public constant LP_SHARE_BPS = 7_000;

    function deploy(address paymentToken, address treasury) external returns (FlowPassHook hook) {
        hook = new FlowPassHook(
            IERC20(paymentToken), treasury, PASS_PRICE, QUOTA_USD_VOLUME, DURATION, DISCOUNT_FEE, LP_SHARE_BPS
        );
    }
}

