// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {FlowPassRouter} from "../src/FlowPassRouter.sol";
import {FlowPassV4Hook, IERC20Like} from "../src/FlowPassV4Hook.sol";
import {UnichainSepoliaConfig as Config} from "./UnichainSepoliaConfig.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

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

/// @notice End-to-end Unichain Sepolia demo with mock ERC20s.
/// @dev Broadcast flow: deploy tokens, mine/deploy hook, deploy router, initialize pool,
///      add liquidity, buy pass, swap through FlowPassRouter, and log remaining quota.
contract DeployUnichainSepoliaMockDemo is Script {
    using PoolIdLibrary for PoolKey;

    struct SortedTokens {
        Currency currency0;
        Currency currency1;
        MockERC20 token0;
        MockERC20 token1;
    }

    struct DemoDeployment {
        FlowPassV4Hook hook;
        FlowPassRouter router;
        PoolKey key;
        PoolId id;
    }

    error WrongChain(uint256 chainId);
    error InvalidAddress();
    error HookAddressMismatch(address expected, address actual);

    function run(address treasury) external {
        if (block.chainid != Config.CHAIN_ID) revert WrongChain(block.chainid);
        if (treasury == address(0)) revert InvalidAddress();

        address trader = msg.sender;

        vm.startBroadcast();

        (MockERC20 tokenA, MockERC20 tokenB) = _deployTokens(trader);
        SortedTokens memory tokens = _sortTokens(tokenA, tokenB);
        DemoDeployment memory deployment = _deployDemoContracts(trader, treasury, tokens);

        _runPoolDemo(deployment, tokens, trader);
        (uint128 remainingUsdVolume, uint64 expiresAt) = deployment.hook.passes(deployment.id, trader);

        vm.stopBroadcast();

        _logDemo(tokenA, tokenB, deployment, remainingUsdVolume, expiresAt);
    }

    function _deployTokens(address trader) internal returns (MockERC20 tokenA, MockERC20 tokenB) {
        tokenA = new MockERC20("FlowPass Demo USDC", "fpUSDC", 18);
        tokenB = new MockERC20("FlowPass Demo USDT0", "fpUSDT0", 18);
        tokenA.mint(trader, Config.MOCK_TOKEN_SUPPLY);
        tokenB.mint(trader, Config.MOCK_TOKEN_SUPPLY);
    }

    function _sortTokens(MockERC20 tokenA, MockERC20 tokenB) internal pure returns (SortedTokens memory tokens) {
        Currency currencyA = Currency.wrap(address(tokenA));
        Currency currencyB = Currency.wrap(address(tokenB));
        (tokens.currency0, tokens.currency1) = currencyA < currencyB ? (currencyA, currencyB) : (currencyB, currencyA);
        tokens.token0 = Currency.unwrap(tokens.currency0) == address(tokenA) ? tokenA : tokenB;
        tokens.token1 = Currency.unwrap(tokens.currency1) == address(tokenA) ? tokenA : tokenB;
    }

    function _deployDemoContracts(address owner, address treasury, SortedTokens memory tokens)
        internal
        returns (DemoDeployment memory deployment)
    {
        IPoolManager manager = IPoolManager(Config.POOL_MANAGER);
        (deployment.hook, deployment.router) = _deployHookAndRouter(owner, treasury, tokens.currency0, manager);
        deployment.key = _buildKey(tokens.currency0, tokens.currency1, deployment.hook);
        deployment.id = deployment.key.toId();
    }

    function _deployHookAndRouter(address owner, address treasury, Currency currency0, IPoolManager manager)
        internal
        returns (FlowPassV4Hook hook, FlowPassRouter router)
    {
        bytes memory constructorArgs = _hookConstructorArgs(owner, treasury, currency0);
        (address expectedHook, bytes32 salt) = HookMiner.find(
            Config.CREATE2_DEPLOYER, Config.HOOK_FLAGS, type(FlowPassV4Hook).creationCode, constructorArgs
        );

        hook = new FlowPassV4Hook{salt: salt}(
            Config.POOL_MANAGER,
            IERC20Like(Currency.unwrap(currency0)),
            owner,
            treasury,
            Config.BASE_FEE,
            Config.MOCK_PASS_PRICE,
            Config.MOCK_QUOTA_USD_VOLUME,
            Config.DURATION,
            Config.DISCOUNT_FEE,
            Config.LP_SHARE_BPS
        );
        router = new FlowPassRouter(manager);
        hook.setTrustedRouter(address(router), true);

        if (address(hook) != expectedHook) revert HookAddressMismatch(expectedHook, address(hook));
        require(uint160(address(hook)) & Hooks.ALL_HOOK_MASK == Config.HOOK_FLAGS, "invalid hook flags");
    }

    function _hookConstructorArgs(address owner, address treasury, Currency currency0)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            Config.POOL_MANAGER,
            IERC20Like(Currency.unwrap(currency0)),
            owner,
            treasury,
            Config.BASE_FEE,
            Config.MOCK_PASS_PRICE,
            Config.MOCK_QUOTA_USD_VOLUME,
            Config.DURATION,
            Config.DISCOUNT_FEE,
            Config.LP_SHARE_BPS
        );
    }

    function _buildKey(Currency currency0, Currency currency1, FlowPassV4Hook hook)
        internal
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: Config.TICK_SPACING,
            hooks: IHooks(address(hook))
        });
    }

    function _runPoolDemo(DemoDeployment memory deployment, SortedTokens memory tokens, address trader) internal {
        IPoolManager manager = IPoolManager(Config.POOL_MANAGER);
        PoolModifyLiquidityTest modifyLiquidityRouter = PoolModifyLiquidityTest(Config.POOL_MODIFY_LIQUIDITY_TEST);

        tokens.token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokens.token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokens.token0.approve(address(deployment.hook), type(uint256).max);
        tokens.token0.approve(address(deployment.router), type(uint256).max);
        tokens.token1.approve(address(deployment.router), type(uint256).max);

        manager.initialize(deployment.key, Config.SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(
            deployment.key,
            ModifyLiquidityParams({
                tickLower: -Config.TICK_SPACING * 2,
                tickUpper: Config.TICK_SPACING * 2,
                liquidityDelta: Config.MOCK_LIQUIDITY_DELTA,
                salt: bytes32(0)
            }),
            ""
        );

        deployment.hook.buyPass(deployment.key);
        deployment.router
            .swapExactInputSingle(
                FlowPassRouter.ExactInputSingleParams({
                    key: deployment.key,
                    zeroForOne: true,
                    amountIn: Config.MOCK_SWAP_AMOUNT_IN,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1,
                    recipient: trader
                })
            );
    }

    function _logDemo(
        MockERC20 tokenA,
        MockERC20 tokenB,
        DemoDeployment memory deployment,
        uint128 remainingUsdVolume,
        uint64 expiresAt
    ) internal pure {
        console2.log("FlowPass demo tokenA", address(tokenA));
        console2.log("FlowPass demo tokenB", address(tokenB));
        console2.log("FlowPass demo hook", address(deployment.hook));
        console2.log("FlowPass demo router", address(deployment.router));
        console2.log("FlowPass pool id");
        console2.logBytes32(PoolId.unwrap(deployment.id));
        console2.log("FlowPass remaining quota", uint256(remainingUsdVolume));
        console2.log("FlowPass pass expires at", uint256(expiresAt));
    }
}
