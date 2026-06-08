// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title FlowPassV4Hook
/// @notice Uniswap v4 IHooks adapter for FlowPass prepaid-volume membership logic.
/// @dev This contract uses real v4 hook signatures. A deploy script still needs to mine
///      an address with BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG before using it with PoolManager.
contract FlowPassV4Hook is IHooks {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;
    using SafeCast for uint256;

    uint16 public constant BPS_DENOMINATOR = 10_000;

    struct Pass {
        uint128 remainingUsdVolume;
        uint64 expiresAt;
    }

    struct Tier {
        uint256 price;
        uint128 quotaUsdVolume;
        uint64 duration;
        uint24 discountFee;
        bool enabled;
    }

    IERC20Like public immutable paymentToken;
    address public immutable poolManager;
    address public owner;
    address public treasury;
    uint24 public baseFee;
    Tier public tier;
    uint16 public lpShareBps;

    mapping(PoolId poolId => mapping(address trader => Pass pass)) public passes;
    mapping(address router => bool trusted) public trustedRouters;
    mapping(PoolId poolId => uint256 amount) public lpRevenueReserve;
    uint256 public treasuryRevenueReserve;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TreasuryUpdated(address indexed treasury);
    event BaseFeeUpdated(uint24 baseFee);
    event TierUpdated(uint256 price, uint128 quotaUsdVolume, uint64 duration, uint24 discountFee, bool enabled);
    event RevenueSplitUpdated(uint16 lpShareBps, uint16 treasuryShareBps);
    event TrustedRouterUpdated(address indexed router, bool trusted);
    event PassPurchased(
        PoolId indexed poolId,
        address indexed trader,
        uint256 price,
        uint128 quotaAdded,
        uint64 expiresAt,
        uint256 lpShare,
        uint256 treasuryShare
    );
    event SwapDiscountEvaluated(
        PoolId indexed poolId, address indexed trader, uint24 fee, bool discounted, uint128 requestedUsdVolume
    );
    event SwapQuotaConsumed(
        PoolId indexed poolId,
        address indexed trader,
        uint128 actualUsdVolume,
        uint128 consumedUsdVolume,
        uint128 remainingUsdVolume
    );
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event LpReserveWithdrawn(PoolId indexed poolId, address indexed to, uint256 amount);

    error HookNotImplemented();
    error NotPoolManager();
    error NotOwner();
    error NotTreasuryOrOwner();
    error InvalidAddress();
    error InvalidSplit();
    error InvalidTier();
    error InvalidFee();
    error InvalidPoolKey();
    error TierDisabled();
    error InvalidHookData();
    error TransferFailed();
    error InsufficientReserve();

    modifier onlyPoolManager() {
        if (msg.sender != poolManager) revert NotPoolManager();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyTreasuryOrOwner() {
        if (msg.sender != owner && msg.sender != treasury) revert NotTreasuryOrOwner();
        _;
    }

    constructor(
        address poolManager_,
        IERC20Like paymentToken_,
        address owner_,
        address treasury_,
        uint24 baseFee_,
        uint256 passPrice_,
        uint128 quotaUsdVolume_,
        uint64 duration_,
        uint24 discountFee_,
        uint16 lpShareBps_
    ) {
        if (
            poolManager_ == address(0) || address(paymentToken_) == address(0) || owner_ == address(0)
                || treasury_ == address(0)
        ) {
            revert InvalidAddress();
        }

        poolManager = poolManager_;
        paymentToken = paymentToken_;
        owner = owner_;
        treasury = treasury_;

        emit OwnershipTransferred(address(0), owner_);
        _setBaseFee(baseFee_);
        _setTier(passPrice_, quotaUsdVolume_, duration_, discountFee_, true);
        _setRevenueSplit(lpShareBps_);
    }

    function treasuryShareBps() public view returns (uint16) {
        return uint16(BPS_DENOMINATOR - lpShareBps);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function setBaseFee(uint24 newBaseFee) external onlyOwner {
        _setBaseFee(newBaseFee);
    }

    function setTier(uint256 price, uint128 quotaUsdVolume, uint64 duration, uint24 discountFee, bool enabled)
        external
        onlyOwner
    {
        _setTier(price, quotaUsdVolume, duration, discountFee, enabled);
    }

    function setRevenueSplit(uint16 newLpShareBps) external onlyOwner {
        _setRevenueSplit(newLpShareBps);
    }

    function setTrustedRouter(address router, bool trusted) external onlyOwner {
        if (router == address(0)) revert InvalidAddress();
        trustedRouters[router] = trusted;
        emit TrustedRouterUpdated(router, trusted);
    }

    function buyPass(PoolKey calldata key) external returns (uint64 expiresAt) {
        _validateFlowPassPool(key);

        Tier memory currentTier = tier;
        if (!currentTier.enabled) revert TierDisabled();

        PoolId id = key.toId();
        _safeTransferFrom(paymentToken, msg.sender, address(this), currentTier.price);

        uint256 lpShare = (currentTier.price * lpShareBps) / BPS_DENOMINATOR;
        uint256 treasuryShare = currentTier.price - lpShare;
        lpRevenueReserve[id] += lpShare;
        treasuryRevenueReserve += treasuryShare;

        Pass storage pass = passes[id][msg.sender];
        pass.remainingUsdVolume += currentTier.quotaUsdVolume;

        uint64 baseExpiry = pass.expiresAt > block.timestamp ? pass.expiresAt : uint64(block.timestamp);
        expiresAt = baseExpiry + currentTier.duration;
        pass.expiresAt = expiresAt;

        emit PassPurchased(
            id, msg.sender, currentTier.price, currentTier.quotaUsdVolume, expiresAt, lpShare, treasuryShare
        );
    }

    function previewSwapFee(PoolKey calldata key, address sender, SwapParams calldata params, bytes calldata hookData)
        public
        view
        returns (uint24 fee, bool discounted, address trader, uint128 requestedUsdVolume)
    {
        _validateFlowPassPool(key);

        PoolId id = key.toId();
        (trader, requestedUsdVolume) = _swapIdentityAndRequestedVolume(sender, params, hookData);
        discounted = _eligibleForDiscount(passes[id][trader], requestedUsdVolume);
        fee = discounted ? tier.discountFee : baseFee;
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (uint24 fee, bool discounted, address trader, uint128 requestedUsdVolume) =
            previewSwapFee(key, sender, params, hookData);

        emit SwapDiscountEvaluated(key.toId(), trader, fee, discounted, requestedUsdVolume);

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        _validateFlowPassPool(key);

        PoolId id = key.toId();
        (address trader, uint128 requestedUsdVolume) = _swapIdentityAndRequestedVolume(sender, params, hookData);
        Pass storage pass = passes[id][trader];

        if (_eligibleForDiscount(pass, requestedUsdVolume)) {
            uint128 actualUsdVolume = _actualInputVolume(params, delta);
            uint128 consumedUsdVolume =
                actualUsdVolume <= pass.remainingUsdVolume ? actualUsdVolume : pass.remainingUsdVolume;
            pass.remainingUsdVolume -= consumedUsdVolume;

            emit SwapQuotaConsumed(id, trader, actualUsdVolume, consumedUsdVolume, pass.remainingUsdVolume);
        }

        return (IHooks.afterSwap.selector, 0);
    }

    function withdrawTreasury(address to, uint256 amount) external onlyTreasuryOrOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > treasuryRevenueReserve) revert InsufficientReserve();

        treasuryRevenueReserve -= amount;
        _safeTransfer(paymentToken, to, amount);
        emit TreasuryWithdrawn(to, amount);
    }

    /// @notice Reserve withdrawal placeholder until PoolManager.donate is wired into the production flow.
    function withdrawLpReserveForDonation(PoolId id, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > lpRevenueReserve[id]) revert InsufficientReserve();

        lpRevenueReserve[id] -= amount;
        _safeTransfer(paymentToken, to, amount);
        emit LpReserveWithdrawn(id, to, amount);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function _swapIdentityAndRequestedVolume(address sender, SwapParams calldata params, bytes calldata hookData)
        internal
        view
        returns (address trader, uint128 requestedUsdVolume)
    {
        if (!trustedRouters[sender] || params.amountSpecified >= 0) return (address(0), 0);

        trader = _decodeTrader(hookData);
        requestedUsdVolume = _toUint128(-params.amountSpecified);
    }

    function _eligibleForDiscount(Pass storage pass, uint128 requestedUsdVolume) internal view returns (bool) {
        return
            requestedUsdVolume > 0 && pass.expiresAt >= block.timestamp && pass.remainingUsdVolume >= requestedUsdVolume;
    }

    function _actualInputVolume(SwapParams calldata params, BalanceDelta delta) internal pure returns (uint128) {
        int128 inputDelta = params.zeroForOne ? delta.amount0() : delta.amount1();
        if (inputDelta >= 0) return 0;
        return _toUint128(-int256(inputDelta));
    }

    function _decodeTrader(bytes calldata hookData) internal pure returns (address trader) {
        if (hookData.length != 32) revert InvalidHookData();
        trader = abi.decode(hookData, (address));
        if (trader == address(0)) revert InvalidHookData();
    }

    function _setBaseFee(uint24 newBaseFee) internal {
        if (!newBaseFee.isValid() || (tier.duration != 0 && tier.discountFee >= newBaseFee)) revert InvalidFee();
        baseFee = newBaseFee;
        emit BaseFeeUpdated(newBaseFee);
    }

    function _setTier(uint256 price, uint128 quotaUsdVolume, uint64 duration, uint24 discountFee, bool enabled)
        internal
    {
        if (price == 0 || quotaUsdVolume == 0 || duration == 0 || !discountFee.isValid() || discountFee >= baseFee) {
            revert InvalidTier();
        }
        tier = Tier({
            price: price, quotaUsdVolume: quotaUsdVolume, duration: duration, discountFee: discountFee, enabled: enabled
        });
        emit TierUpdated(price, quotaUsdVolume, duration, discountFee, enabled);
    }

    function _setRevenueSplit(uint16 newLpShareBps) internal {
        if (newLpShareBps > BPS_DENOMINATOR) revert InvalidSplit();
        lpShareBps = newLpShareBps;
        emit RevenueSplitUpdated(newLpShareBps, uint16(BPS_DENOMINATOR - newLpShareBps));
    }

    function _validateFlowPassPool(PoolKey calldata key) internal view {
        if (address(key.hooks) != address(this) || !key.fee.isDynamicFee()) revert InvalidPoolKey();
    }

    function _toUint128(int256 amount) internal pure returns (uint128) {
        if (amount < 0 || amount > int256(uint256(type(uint128).max))) revert InvalidHookData();
        return uint256(amount).toUint128();
    }

    function _safeTransferFrom(IERC20Like token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeTransfer(IERC20Like token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
