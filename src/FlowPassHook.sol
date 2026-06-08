// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title FlowPassHook
/// @notice MVP hook-shaped contract for a prepaid volume pass on a Uniswap v4-style pool.
/// @dev This first local-demo version keeps the core economics independent from v4-core
///      imports so it can be tested locally before wiring into BaseHook/PoolManager.
contract FlowPassHook {
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint24 public constant MAX_LP_FEE = 1_000_000;

    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

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

    IERC20 public immutable paymentToken;
    address public owner;
    address public treasury;
    Tier public tier;
    uint16 public lpShareBps;

    mapping(bytes32 poolId => mapping(address trader => Pass pass)) public passes;
    mapping(address router => bool trusted) public trustedRouters;
    mapping(bytes32 poolId => uint256 amount) public lpRevenueReserve;
    uint256 public treasuryRevenueReserve;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TreasuryUpdated(address indexed treasury);
    event TierUpdated(uint256 price, uint128 quotaUsdVolume, uint64 duration, uint24 discountFee, bool enabled);
    event RevenueSplitUpdated(uint16 lpShareBps, uint16 treasuryShareBps);
    event TrustedRouterUpdated(address indexed router, bool trusted);
    event PassPurchased(
        bytes32 indexed poolId,
        address indexed trader,
        uint256 price,
        uint128 quotaAdded,
        uint64 expiresAt,
        uint256 lpShare,
        uint256 treasuryShare
    );
    event SwapRecorded(
        bytes32 indexed poolId,
        address indexed trader,
        uint24 fee,
        bool discounted,
        uint128 requestedUsdVolume,
        uint128 actualUsdVolume,
        uint128 consumedUsdVolume,
        uint128 remainingUsdVolume
    );
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event LpReserveWithdrawn(bytes32 indexed poolId, address indexed to, uint256 amount);

    error NotOwner();
    error NotTreasuryOrOwner();
    error InvalidAddress();
    error InvalidSplit();
    error InvalidTier();
    error InvalidPoolKey();
    error TierDisabled();
    error NotTrustedRouter();
    error InvalidHookData();
    error TransferFailed();
    error InsufficientReserve();
    error ActualVolumeExceedsRequested();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyTreasuryOrOwner() {
        if (msg.sender != owner && msg.sender != treasury) revert NotTreasuryOrOwner();
        _;
    }

    constructor(
        IERC20 paymentToken_,
        address treasury_,
        uint256 passPrice_,
        uint128 quotaUsdVolume_,
        uint64 duration_,
        uint24 discountFee_,
        uint16 lpShareBps_
    ) {
        if (address(paymentToken_) == address(0) || treasury_ == address(0)) revert InvalidAddress();

        paymentToken = paymentToken_;
        owner = msg.sender;
        treasury = treasury_;

        emit OwnershipTransferred(address(0), msg.sender);
        _setTier(passPrice_, quotaUsdVolume_, duration_, discountFee_, true);
        _setRevenueSplit(lpShareBps_);
    }

    function poolId(PoolKey calldata key) public pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks));
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

        bytes32 id = poolId(key);
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

    function previewSwapFee(PoolKey calldata key, address trader, bool exactInput, uint128 requestedUsdVolume)
        public
        view
        returns (uint24 fee, bool discounted)
    {
        _validateFlowPassPool(key);

        bytes32 id = poolId(key);
        discounted = _discountApplies(passes[id][trader], key.fee, exactInput, requestedUsdVolume);
        fee = discounted ? tier.discountFee : key.fee;
    }

    function recordSwap(
        PoolKey calldata key,
        bytes calldata hookData,
        bool exactInput,
        uint128 requestedUsdVolume,
        uint128 actualUsdVolume
    ) external returns (uint24 fee, bool discounted, uint128 consumedUsdVolume) {
        if (!trustedRouters[msg.sender]) revert NotTrustedRouter();
        _validateFlowPassPool(key);
        if (exactInput && actualUsdVolume > requestedUsdVolume) revert ActualVolumeExceedsRequested();

        address trader = _decodeTrader(hookData);
        bytes32 id = poolId(key);
        Pass storage pass = passes[id][trader];

        discounted = _discountApplies(pass, key.fee, exactInput, requestedUsdVolume);
        fee = discounted ? tier.discountFee : key.fee;

        if (discounted && actualUsdVolume > 0) {
            consumedUsdVolume = actualUsdVolume <= pass.remainingUsdVolume ? actualUsdVolume : pass.remainingUsdVolume;
            pass.remainingUsdVolume -= consumedUsdVolume;
        }

        emit SwapRecorded(
            id, trader, fee, discounted, requestedUsdVolume, actualUsdVolume, consumedUsdVolume, pass.remainingUsdVolume
        );
    }

    function withdrawTreasury(address to, uint256 amount) external onlyTreasuryOrOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > treasuryRevenueReserve) revert InsufficientReserve();

        treasuryRevenueReserve -= amount;
        _safeTransfer(paymentToken, to, amount);
        emit TreasuryWithdrawn(to, amount);
    }

    /// @notice MVP placeholder for the LP share until v4 donate integration is finalized.
    /// @dev In the real hook, this reserve should be donated to the pool or routed to a dedicated LP rewards flow.
    function withdrawLpReserveForDonation(bytes32 id, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > lpRevenueReserve[id]) revert InsufficientReserve();

        lpRevenueReserve[id] -= amount;
        _safeTransfer(paymentToken, to, amount);
        emit LpReserveWithdrawn(id, to, amount);
    }

    function _setTier(uint256 price, uint128 quotaUsdVolume, uint64 duration, uint24 discountFee, bool enabled)
        internal
    {
        if (price == 0 || quotaUsdVolume == 0 || duration == 0 || discountFee > MAX_LP_FEE) {
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
        if (key.hooks != address(this)) revert InvalidPoolKey();
    }

    function _discountApplies(Pass storage pass, uint24 poolFee, bool exactInput, uint128 requestedUsdVolume)
        internal
        view
        returns (bool)
    {
        return tier.discountFee < poolFee && _eligibleForDiscount(pass, exactInput, requestedUsdVolume);
    }

    function _eligibleForDiscount(Pass storage pass, bool exactInput, uint128 requestedUsdVolume)
        internal
        view
        returns (bool)
    {
        return exactInput && requestedUsdVolume > 0 && pass.expiresAt >= block.timestamp
            && pass.remainingUsdVolume >= requestedUsdVolume;
    }

    function _decodeTrader(bytes calldata hookData) internal pure returns (address trader) {
        if (hookData.length != 32) revert InvalidHookData();
        trader = abi.decode(hookData, (address));
        if (trader == address(0)) revert InvalidHookData();
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
