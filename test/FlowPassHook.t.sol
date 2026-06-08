// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassHook, IERC20} from "../src/FlowPassHook.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFlowPassRouter} from "./mocks/MockFlowPassRouter.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
    function expectRevert(bytes4 selector) external;
}

contract FlowPassHookTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint24 internal constant BASE_FEE = 100;
    uint24 internal constant DISCOUNT_FEE = 50;
    uint256 internal constant PASS_PRICE = 300e6;
    uint128 internal constant QUOTA = 10_000_000e6;
    uint64 internal constant DURATION = 7 days;
    uint16 internal constant LP_SHARE_BPS = 7_000;

    MockERC20 internal usdc;
    FlowPassHook internal hook;
    MockFlowPassRouter internal router;
    FlowPassHook.PoolKey internal key;
    bytes32 internal id;

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "USDC", 6);
        hook = new FlowPassHook(
            IERC20(address(usdc)), address(this), PASS_PRICE, QUOTA, DURATION, DISCOUNT_FEE, LP_SHARE_BPS
        );
        router = new MockFlowPassRouter(hook);
        hook.setTrustedRouter(address(router), true);

        key = FlowPassHook.PoolKey({
            currency0: address(usdc), currency1: address(0x2222), fee: BASE_FEE, tickSpacing: 1, hooks: address(hook)
        });
        id = hook.poolId(key);

        usdc.mint(address(this), 1_000e6);
        usdc.approve(address(hook), type(uint256).max);
    }

    function testBuyPassRecordsQuotaAndRevenueSplit() public {
        hook.buyPass(key);

        (uint128 remainingUsdVolume, uint64 expiresAt) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, QUOTA, "remaining quota");
        assertEqUint(expiresAt, block.timestamp + DURATION, "expiry");
        assertEqUint(usdc.balanceOf(address(hook)), PASS_PRICE, "hook balance");
        assertEqUint(hook.lpRevenueReserve(id), 210e6, "lp reserve");
        assertEqUint(hook.treasuryRevenueReserve(), 90e6, "treasury reserve");
    }

    function testBuyPassRejectsPoolKeyForAnotherHook() public {
        FlowPassHook.PoolKey memory wrongKey = key;
        wrongKey.hooks = address(0xBAD);

        vm.expectRevert(FlowPassHook.InvalidPoolKey.selector);
        hook.buyPass(wrongKey);
    }

    function testActivePassReceivesDiscountAndConsumesActualVolume() public {
        hook.buyPass(key);

        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactInput(key, 1_000_000e6, 900_000e6);

        assertEqUint(fee, DISCOUNT_FEE, "discount fee");
        assertTrue(discounted, "discounted");
        assertEqUint(consumed, 900_000e6, "consumed");

        (uint128 remainingUsdVolume,) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, QUOTA - 900_000e6, "remaining quota");
    }

    function testPoolFeeBelowDiscountDoesNotConsumeQuota() public {
        hook.buyPass(key);

        FlowPassHook.PoolKey memory lowFeeKey = key;
        lowFeeKey.fee = DISCOUNT_FEE;
        bytes32 lowFeePoolId = hook.poolId(lowFeeKey);

        hook.buyPass(lowFeeKey);
        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactInput(lowFeeKey, 1_000_000e6, 900_000e6);

        assertEqUint(fee, DISCOUNT_FEE, "pool fee");
        assertFalse(discounted, "not discounted");
        assertEqUint(consumed, 0, "no quota consumed");

        (uint128 remainingUsdVolume,) = hook.passes(lowFeePoolId, address(this));
        assertEqUint(remainingUsdVolume, QUOTA, "quota unchanged");
    }

    function testNoPassUsesBaseFee() public {
        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactInput(key, 1_000_000e6, 1_000_000e6);

        assertEqUint(fee, BASE_FEE, "base fee");
        assertFalse(discounted, "not discounted");
        assertEqUint(consumed, 0, "no quota consumed");
    }

    function testInsufficientQuotaUsesBaseFee() public {
        hook.buyPass(key);

        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactInput(key, QUOTA + 1, QUOTA + 1);

        assertEqUint(fee, BASE_FEE, "base fee");
        assertFalse(discounted, "not discounted");
        assertEqUint(consumed, 0, "no quota consumed");

        (uint128 remainingUsdVolume,) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, QUOTA, "quota unchanged");
    }

    function testExactOutputDoesNotReceiveDiscount() public {
        hook.buyPass(key);

        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactOutput(key, 1_000_000e6, 1_000_000e6);

        assertEqUint(fee, BASE_FEE, "base fee");
        assertFalse(discounted, "not discounted");
        assertEqUint(consumed, 0, "no quota consumed");
    }

    function testExpiredPassUsesBaseFee() public {
        hook.buyPass(key);
        vm.warp(block.timestamp + DURATION + 1);

        (uint24 fee, bool discounted, uint128 consumed) = router.swapExactInput(key, 1_000_000e6, 1_000_000e6);

        assertEqUint(fee, BASE_FEE, "base fee");
        assertFalse(discounted, "not discounted");
        assertEqUint(consumed, 0, "no quota consumed");
    }

    function testTopUpAddsQuotaAndExtendsExpiry() public {
        hook.buyPass(key);
        (, uint64 firstExpiry) = hook.passes(id, address(this));

        hook.buyPass(key);

        (uint128 remainingUsdVolume, uint64 secondExpiry) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, QUOTA * 2, "stacked quota");
        assertEqUint(secondExpiry, firstExpiry + DURATION, "extended expiry");
    }

    function testUntrustedRouterCannotRecordSwap() public {
        vm.expectRevert(FlowPassHook.NotTrustedRouter.selector);
        hook.recordSwap(key, abi.encode(address(this)), true, 1_000_000e6, 1_000_000e6);
    }

    function testUnauthorizedCannotUpdateTier() public {
        UnauthorizedCaller caller = new UnauthorizedCaller(hook);
        bool success = caller.trySetTier();
        assertFalse(success, "unauthorized update blocked");
    }

    function testTreasuryWithdraw() public {
        hook.buyPass(key);

        hook.withdrawTreasury(address(0xBEEF), 90e6);

        assertEqUint(hook.treasuryRevenueReserve(), 0, "treasury reserve");
        assertEqUint(usdc.balanceOf(address(0xBEEF)), 90e6, "treasury paid");
    }

    function assertEqUint(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function assertTrue(bool value, string memory message) internal pure {
        require(value, message);
    }

    function assertFalse(bool value, string memory message) internal pure {
        require(!value, message);
    }
}

contract UnauthorizedCaller {
    FlowPassHook internal hook;

    constructor(FlowPassHook hook_) {
        hook = hook_;
    }

    function trySetTier() external returns (bool success) {
        (success,) =
            address(hook).call(abi.encodeCall(FlowPassHook.setTier, (1, uint128(1), uint64(1), uint24(1), true)));
    }
}
