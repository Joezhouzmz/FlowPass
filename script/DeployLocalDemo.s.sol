// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassHook, IERC20} from "../src/FlowPassHook.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockFlowPassRouter} from "../test/mocks/MockFlowPassRouter.sol";

/// @notice Local demo deployment helper.
/// @dev Deploys mock USDC, the FlowPass hook MVP, and a trusted mock router.
contract DeployLocalDemo {
    uint256 public constant PASS_PRICE = 300e6;
    uint128 public constant QUOTA_USD_VOLUME = 10_000_000e6;
    uint64 public constant DURATION = 7 days;
    uint24 public constant DISCOUNT_FEE = 50;
    uint16 public constant LP_SHARE_BPS = 7_000;

    function run() external returns (MockERC20 usdc, FlowPassHook hook, MockFlowPassRouter router) {
        usdc = new MockERC20("Mock USDC", "USDC", 6);
        hook = new FlowPassHook(
            IERC20(address(usdc)), msg.sender, PASS_PRICE, QUOTA_USD_VOLUME, DURATION, DISCOUNT_FEE, LP_SHARE_BPS
        );
        router = new MockFlowPassRouter(hook);
        hook.setTrustedRouter(address(router), true);
    }
}

