// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FlowPassV4Hook, IERC20Like} from "../src/FlowPassV4Hook.sol";
import {FlowPassRouter} from "../src/FlowPassRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

interface Vm {
    function expectRevert(bytes4 selector) external;
}

contract FlowPassV4PoolManagerTest {
    using PoolIdLibrary for PoolKey;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint24 internal constant BASE_FEE = 100;
    uint24 internal constant DISCOUNT_FEE = 50;
    uint256 internal constant PASS_PRICE = 300e18;
    uint128 internal constant QUOTA = 10_000_000;
    uint64 internal constant DURATION = 7 days;
    uint16 internal constant LP_SHARE_BPS = 7_000;
    int256 internal constant SWAP_AMOUNT = -1_000_000;

    PoolManager internal manager;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    FlowPassRouter internal flowPassRouter;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    FlowPassV4Hook internal hook;
    PoolKey internal key;
    PoolId internal id;

    function setUp() public {
        manager = new PoolManager(address(this));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        flowPassRouter = new FlowPassRouter(manager);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        tokenA.mint(address(this), 1_000_000e18);
        tokenB.mint(address(this), 1_000_000e18);

        Currency currencyA = Currency.wrap(address(tokenA));
        Currency currencyB = Currency.wrap(address(tokenB));
        (Currency currency0, Currency currency1) =
            currencyA < currencyB ? (currencyA, currencyB) : (currencyB, currencyA);

        bytes memory constructorArgs = abi.encode(
            address(manager),
            IERC20Like(Currency.unwrap(currency0)),
            address(this),
            address(this),
            BASE_FEE,
            PASS_PRICE,
            QUOTA,
            DURATION,
            DISCOUNT_FEE,
            LP_SHARE_BPS
        );
        uint160 flags = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        (, bytes32 salt) = HookMiner.find(address(this), flags, type(FlowPassV4Hook).creationCode, constructorArgs);

        hook = new FlowPassV4Hook{salt: salt}(
            address(manager),
            IERC20Like(Currency.unwrap(currency0)),
            address(this),
            address(this),
            BASE_FEE,
            PASS_PRICE,
            QUOTA,
            DURATION,
            DISCOUNT_FEE,
            LP_SHARE_BPS
        );

        require(uint160(address(hook)) & Hooks.ALL_HOOK_MASK == flags, "hook flags");
        hook.setTrustedRouter(address(flowPassRouter), true);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        id = key.toId();

        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenA.approve(address(flowPassRouter), type(uint256).max);
        tokenB.approve(address(flowPassRouter), type(uint256).max);
        tokenA.approve(address(hook), type(uint256).max);
        tokenB.approve(address(hook), type(uint256).max);

        manager.initialize(key, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)}), ""
        );
    }

    function testPoolManagerSwapConsumesQuotaThroughRealHooks() public {
        hook.buyPass(key);

        flowPassRouter.swapExactInputSingle(
            FlowPassRouter.ExactInputSingleParams({
                key: key,
                zeroForOne: true,
                amountIn: uint256(-SWAP_AMOUNT),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
                recipient: address(this)
            })
        );

        (uint128 remainingUsdVolume,) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, QUOTA - uint128(uint256(-SWAP_AMOUNT)), "quota consumed");
    }

    function testPoolManagerSwapWithoutPassUsesBaseFeePath() public {
        flowPassRouter.swapExactInputSingle(
            FlowPassRouter.ExactInputSingleParams({
                key: key,
                zeroForOne: true,
                amountIn: uint256(-SWAP_AMOUNT),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
                recipient: address(this)
            })
        );

        (uint128 remainingUsdVolume,) = hook.passes(id, address(this));
        assertEqUint(remainingUsdVolume, 0, "no pass");
    }

    function testFlowPassRouterRejectsZeroAmountIn() public {
        vm.expectRevert(FlowPassRouter.ZeroAmountIn.selector);

        flowPassRouter.swapExactInputSingle(
            FlowPassRouter.ExactInputSingleParams({
                key: key,
                zeroForOne: true,
                amountIn: 0,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
                recipient: address(this)
            })
        );
    }

    function testFlowPassRouterRejectsZeroManager() public {
        vm.expectRevert(FlowPassRouter.InvalidManager.selector);
        new FlowPassRouter(IPoolManager(address(0)));
    }

    function testFlowPassRouterUnlockCallbackOnlyPoolManager() public {
        vm.expectRevert(FlowPassRouter.NotPoolManager.selector);
        flowPassRouter.unlockCallback("");
    }

    function testFlowPassRouterRejectsInsufficientOutputAmount() public {
        vm.expectRevert(FlowPassRouter.InsufficientOutputAmount.selector);

        flowPassRouter.swapExactInputSingle(
            FlowPassRouter.ExactInputSingleParams({
                key: key,
                zeroForOne: true,
                amountIn: uint256(-SWAP_AMOUNT),
                amountOutMinimum: type(uint256).max,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
                recipient: address(this)
            })
        );
    }

    function assertEqUint(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }
}
