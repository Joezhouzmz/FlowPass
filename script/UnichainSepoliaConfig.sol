// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

library UnichainSepoliaConfig {
    uint256 internal constant CHAIN_ID = 1301;

    address internal constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address internal constant POOL_MODIFY_LIQUIDITY_TEST = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 internal constant HOOK_FLAGS = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    uint24 internal constant BASE_FEE = 100;
    uint24 internal constant DISCOUNT_FEE = 50;
    int24 internal constant TICK_SPACING = 60;
    uint64 internal constant DURATION = 7 days;
    uint16 internal constant LP_SHARE_BPS = 7_000;

    uint256 internal constant USDC_PASS_PRICE = 300e6;
    uint128 internal constant USDC_QUOTA_USD_VOLUME = 10_000_000e6;

    uint256 internal constant MOCK_PASS_PRICE = 300e18;
    uint128 internal constant MOCK_QUOTA_USD_VOLUME = 10_000_000e18;
    uint256 internal constant MOCK_TOKEN_SUPPLY = 1_000_000e18;
    int256 internal constant MOCK_LIQUIDITY_DELTA = 1e18;
    uint256 internal constant MOCK_SWAP_AMOUNT_IN = 1_000e18;
}
