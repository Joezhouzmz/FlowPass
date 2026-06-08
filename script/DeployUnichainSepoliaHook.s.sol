// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {FlowPassRouter} from "../src/FlowPassRouter.sol";
import {FlowPassV4Hook, IERC20Like} from "../src/FlowPassV4Hook.sol";
import {UnichainSepoliaConfig as Config} from "./UnichainSepoliaConfig.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

/// @notice Deploys FlowPass hook + router against the public Unichain Sepolia v4 PoolManager.
/// @dev Does not read RPC URLs, private keys, or wallet config. Pass those explicitly to forge.
contract DeployUnichainSepoliaHook is Script {
    struct DeployParams {
        address paymentToken;
        address owner;
        address treasury;
        uint256 passPrice;
        uint128 quotaUsdVolume;
        uint64 duration;
        uint24 baseFee;
        uint24 discountFee;
        uint16 lpShareBps;
    }

    error WrongChain(uint256 chainId);
    error InvalidAddress();
    error HookAddressMismatch(address expected, address actual);

    function deploy(address paymentToken, address treasury)
        external
        returns (FlowPassV4Hook hook, FlowPassRouter router)
    {
        return deployWithParams(
            paymentToken,
            treasury,
            Config.USDC_PASS_PRICE,
            Config.USDC_QUOTA_USD_VOLUME,
            Config.DURATION,
            Config.BASE_FEE,
            Config.DISCOUNT_FEE,
            Config.LP_SHARE_BPS
        );
    }

    function deployWithParams(
        address paymentToken,
        address treasury,
        uint256 passPrice,
        uint128 quotaUsdVolume,
        uint64 duration,
        uint24 baseFee,
        uint24 discountFee,
        uint16 lpShareBps
    ) public returns (FlowPassV4Hook hook, FlowPassRouter router) {
        if (block.chainid != Config.CHAIN_ID) revert WrongChain(block.chainid);
        if (paymentToken == address(0) || treasury == address(0)) revert InvalidAddress();

        DeployParams memory params = DeployParams({
            paymentToken: paymentToken,
            owner: msg.sender,
            treasury: treasury,
            passPrice: passPrice,
            quotaUsdVolume: quotaUsdVolume,
            duration: duration,
            baseFee: baseFee,
            discountFee: discountFee,
            lpShareBps: lpShareBps
        });

        bytes memory constructorArgs = _constructorArgs(params);
        (address expectedHook, bytes32 salt) = HookMiner.find(
            Config.CREATE2_DEPLOYER, Config.HOOK_FLAGS, type(FlowPassV4Hook).creationCode, constructorArgs
        );

        console2.log("FlowPass expected hook", expectedHook);
        console2.log("FlowPass salt");
        console2.logBytes32(salt);

        vm.startBroadcast();

        hook = _deployHook(params, salt);
        router = new FlowPassRouter(IPoolManager(Config.POOL_MANAGER));
        hook.setTrustedRouter(address(router), true);

        vm.stopBroadcast();

        if (address(hook) != expectedHook) revert HookAddressMismatch(expectedHook, address(hook));
        require(uint160(address(hook)) & Hooks.ALL_HOOK_MASK == Config.HOOK_FLAGS, "invalid hook flags");

        console2.log("FlowPass hook", address(hook));
        console2.log("FlowPass router", address(router));
    }

    function _constructorArgs(DeployParams memory params) internal pure returns (bytes memory) {
        return abi.encode(
            Config.POOL_MANAGER,
            IERC20Like(params.paymentToken),
            params.owner,
            params.treasury,
            params.baseFee,
            params.passPrice,
            params.quotaUsdVolume,
            params.duration,
            params.discountFee,
            params.lpShareBps
        );
    }

    function _deployHook(DeployParams memory params, bytes32 salt) internal returns (FlowPassV4Hook hook) {
        hook = new FlowPassV4Hook{salt: salt}(
            Config.POOL_MANAGER,
            IERC20Like(params.paymentToken),
            params.owner,
            params.treasury,
            params.baseFee,
            params.passPrice,
            params.quotaUsdVolume,
            params.duration,
            params.discountFee,
            params.lpShareBps
        );
    }
}
