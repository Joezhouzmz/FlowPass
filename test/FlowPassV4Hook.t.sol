// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassV4Hook, IERC20Like} from "../src/FlowPassV4Hook.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
    function expectRevert(bytes4 selector) external;
}

contract FlowPassV4HookTest {
    using PoolIdLibrary for PoolKey;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint24 internal constant BASE_FEE = 100;
    uint24 internal constant DISCOUNT_FEE = 50;
    uint256 internal constant PASS_PRICE = 300e6;
    uint128 internal constant QUOTA = 10_000_000e6;
    uint64 internal constant DURATION = 7 days;
    uint16 internal constant LP_SHARE_BPS = 7_000;

    address internal constant POOL_MANAGER = address(0x1234);
    address internal constant ROUTER = address(0xCAFE);
    address internal constant TRADER = address(0xBEEF);

    MockERC20 internal usdc;
    FlowPassV4Hook internal hook;
    PoolKey internal key;
    PoolId internal id;

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "USDC", 6);
        hook = new FlowPassV4Hook(
            POOL_MANAGER,
            IERC20Like(address(usdc)),
            address(this),
            address(this),
            BASE_FEE,
            PASS_PRICE,
            QUOTA,
            DURATION,
            DISCOUNT_FEE,
            LP_SHARE_BPS
        );
        hook.setTrustedRouter(ROUTER, true);

        key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(0x2222)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        id = key.toId();

        usdc.mint(TRADER, 1_000e6);
        vmPrank(TRADER);
        usdc.approve(address(hook), type(uint256).max);
    }

    function testBuyPassUsesV4PoolIdAndRevenueSplit() public {
        vmPrank(TRADER);
        hook.buyPass(key);

        (uint128 remainingUsdVolume, uint64 expiresAt) = hook.passes(id, TRADER);
        assertEqUint(remainingUsdVolume, QUOTA, "remaining quota");
        assertEqUint(expiresAt, block.timestamp + DURATION, "expiry");
        assertEqUint(hook.lpRevenueReserve(id), 210e6, "lp reserve");
        assertEqUint(hook.treasuryRevenueReserve(), 90e6, "treasury reserve");
    }

    function testConstructorUsesExplicitOwner() public {
        FlowPassV4Hook ownedHook = new FlowPassV4Hook(
            POOL_MANAGER,
            IERC20Like(address(usdc)),
            TRADER,
            address(this),
            BASE_FEE,
            PASS_PRICE,
            QUOTA,
            DURATION,
            DISCOUNT_FEE,
            LP_SHARE_BPS
        );

        assertEqAddress(ownedHook.owner(), TRADER, "explicit owner");
    }

    function testBuyPassRejectsStaticFeePool() public {
        PoolKey memory staticFeeKey = key;
        staticFeeKey.fee = BASE_FEE;

        vmPrank(TRADER);
        vm.expectRevert(FlowPassV4Hook.InvalidPoolKey.selector);
        hook.buyPass(staticFeeKey);
    }

    function testBuyPassRejectsPoolKeyForAnotherHook() public {
        PoolKey memory wrongHookKey = key;
        wrongHookKey.hooks = IHooks(address(0xBAD));

        vmPrank(TRADER);
        vm.expectRevert(FlowPassV4Hook.InvalidPoolKey.selector);
        hook.buyPass(wrongHookKey);
    }

    function testBeforeSwapReturnsDiscountOverrideForActivePass() public {
        buyPassAsTrader();
        SwapParams memory params = exactInputParams(1_000_000e6, true);

        vmPrank(POOL_MANAGER);
        (bytes4 selector,, uint24 feeOverride) = hook.beforeSwap(ROUTER, key, params, abi.encode(TRADER));

        assertEqBytes4(selector, IHooks.beforeSwap.selector, "selector");
        assertEqUint(feeOverride, DISCOUNT_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG, "discount override");
    }

    function testBeforeSwapReturnsBaseOverrideWithoutPass() public {
        SwapParams memory params = exactInputParams(1_000_000e6, true);

        vmPrank(POOL_MANAGER);
        (,, uint24 feeOverride) = hook.beforeSwap(ROUTER, key, params, abi.encode(TRADER));

        assertEqUint(feeOverride, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG, "base override");
    }

    function testBeforeSwapRejectsStaticFeePool() public {
        PoolKey memory staticFeeKey = key;
        staticFeeKey.fee = BASE_FEE;
        SwapParams memory params = exactInputParams(1_000_000e6, true);

        vmPrank(POOL_MANAGER);
        vm.expectRevert(FlowPassV4Hook.InvalidPoolKey.selector);
        hook.beforeSwap(ROUTER, staticFeeKey, params, abi.encode(TRADER));
    }

    function testAfterSwapConsumesActualInputVolume() public {
        buyPassAsTrader();
        SwapParams memory params = exactInputParams(1_000_000e6, true);

        vmPrank(POOL_MANAGER);
        hook.afterSwap(ROUTER, key, params, toBalanceDelta(-900_000e6, 899_000e6), abi.encode(TRADER));

        (uint128 remainingUsdVolume,) = hook.passes(id, TRADER);
        assertEqUint(remainingUsdVolume, QUOTA - 900_000e6, "remaining quota");
    }

    function testExactOutputGetsBaseFeeAndConsumesNoQuota() public {
        buyPassAsTrader();
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: int256(1_000_000e6), sqrtPriceLimitX96: 0});

        vmPrank(POOL_MANAGER);
        (,, uint24 feeOverride) = hook.beforeSwap(ROUTER, key, params, abi.encode(TRADER));

        vmPrank(POOL_MANAGER);
        hook.afterSwap(ROUTER, key, params, toBalanceDelta(-1_001_000e6, 1_000_000e6), abi.encode(TRADER));

        (uint128 remainingUsdVolume,) = hook.passes(id, TRADER);
        assertEqUint(feeOverride, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG, "base override");
        assertEqUint(remainingUsdVolume, QUOTA, "quota unchanged");
    }

    function testCannotSetDiscountFeeAtOrAboveBaseFee() public {
        vm.expectRevert(FlowPassV4Hook.InvalidTier.selector);
        hook.setTier(PASS_PRICE, QUOTA, DURATION, BASE_FEE, true);
    }

    function testCannotSetBaseFeeAtOrBelowDiscountFee() public {
        vm.expectRevert(FlowPassV4Hook.InvalidFee.selector);
        hook.setBaseFee(DISCOUNT_FEE);
    }

    function testOnlyPoolManagerCanCallSwapHooks() public {
        SwapParams memory params = exactInputParams(1_000_000e6, true);

        vm.expectRevert(FlowPassV4Hook.NotPoolManager.selector);
        hook.beforeSwap(ROUTER, key, params, abi.encode(TRADER));
    }

    function testUntrustedRouterGetsBaseFeeAndConsumesNoQuota() public {
        buyPassAsTrader();
        SwapParams memory params = exactInputParams(1_000_000e6, true);
        address untrustedRouter = address(0xBAD);

        vmPrank(POOL_MANAGER);
        (,, uint24 feeOverride) = hook.beforeSwap(untrustedRouter, key, params, abi.encode(TRADER));

        vmPrank(POOL_MANAGER);
        hook.afterSwap(untrustedRouter, key, params, toBalanceDelta(-1_000_000e6, 999_000e6), abi.encode(TRADER));

        (uint128 remainingUsdVolume,) = hook.passes(id, TRADER);
        assertEqUint(feeOverride, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG, "base override");
        assertEqUint(remainingUsdVolume, QUOTA, "quota unchanged");
    }

    function buyPassAsTrader() internal {
        vmPrank(TRADER);
        hook.buyPass(key);
    }

    function exactInputParams(uint128 amount, bool zeroForOne) internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(uint256(amount)), sqrtPriceLimitX96: 0});
    }

    function vmPrank(address caller) internal {
        (bool success,) = address(vm).call(abi.encodeWithSignature("prank(address)", caller));
        require(success, "vm prank failed");
    }

    function assertEqUint(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function assertEqBytes4(bytes4 actual, bytes4 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function assertEqAddress(address actual, address expected, string memory message) internal pure {
        require(actual == expected, message);
    }
}
