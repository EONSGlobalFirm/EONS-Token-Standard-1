// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
/**
 * @title ETS-1 — EONS Token Standard 1 is a Fungible Token Standard With Customizable Actions
 * @author Katascha White (Katascha.White@outlook.com) @dev yahoo handle since 2003
 *EONS GLOBAL FIRM CONTRACT
 * @notice
 * Standard for the EONS (E) token-Powered by ETS-1
 *Copyright 2026
 *
 * Features:
 * - Fixed supply of 100 billion E
 * - Entire supply created during deployment
 * - Initial sales inventory assigned to the contract
 * - Transferable Ownership with acceptance
 * - No minting after deployment
 * - Owner/controller identification
 * - Emergency Global pause mechanism
 * - Circuit breaker (auto-pause on large or rate-limited transfers)access for all token holders
 * - Customizable action registry
 */
interface IETS1 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}
interface IETS1PriceFeed {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
contract ETS1 {
    // Compact replacement for long revert strings; conditions and control flow are unchanged.
    error ETS1Error();
    /*
     * ETS-1 (EONS Token Standard 1)
     *
     * TOKEN FEATURES
     * - Fixed Supply
     * - 100 Billion Maximum Supply
     * - Ownership Transfer
     * - Pause / Unpause
     * - Address Blocklist
     * - Allowances
     * - Batch Transfers
     * - Burn Function
     * - Asset Tracking
     * - Traceable Transfers
     *
     * SECURITY
     * - Reentrancy Protection
     * - Global Circuit Breaker
     * - Personal Circuit Breaker
     * - Emergency Pause
     * - Oracle Validation
     *
     * COMMERCE
     * - USDC Purchases
     * - Native Coin Purchases
     * - Automatic Revenue Splitting
     * - Purchase History
     *
     * GOVERNANCE
     * - Ownership Acceptance
     * - Action Registry
     * - Content Hash Registry
     *
     * ANALYTICS
     * - Asset Trace History
     * - Purchase History
     * - Supply Tracking
     * - Holder Verification
     * - Circulating Supply
     */
    // =============================================================
    // TOKEN DATA
    // =============================================================
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18;
    uint256 public constant INITIAL_SALES_INVENTORY = 100_000_000 * 10 ** 18;
    uint256 private _totalSupply;
    // Purchase price: 2 USDC for 1 whole EONS.
    uint256 public constant USDC_PRICE_PER_EONS = 2;
    uint256 private constant TOKEN_UNIT = 10 ** 18;
    bytes32 public contentHash;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public burnedAmount;
    // =============================================================
    // OWNER DATA
    // =============================================================
    address private _owner;
    address public pendingOwner;
    modifier onlyOwner() {
        if (!(msg.sender == _owner)) revert ETS1Error();
        _;
    }
    modifier notPaused() {
        if (!(!paused)) revert ETS1Error();
        _;
    }
    // Reject state-changing calls from addresses marked by the owner.
    // This is address-based blocking, not automatic bot detection.
    modifier notBlockedCaller() {
        if (!(!_blocked[msg.sender])) revert ETS1Error();
        _;
    }
    // Automatically throttles rapid repeated calls without requiring the
    // owner to identify or manually list an address first.
    modifier automaticBotThrottle() {
        BotActivity storage activity = _botActivity[msg.sender];
        if (
            activity.windowStart == 0 ||
            block.timestamp >= activity.windowStart + BOT_WINDOW_SECONDS
        ) {
            activity.windowStart = block.timestamp;
            activity.calls = 0;
        }
        if (!(activity.calls < BOT_MAX_CALLS_PER_WINDOW)) revert ETS1Error();
        activity.calls += 1;
        _;
    }
    function botActivity(address account)
        external
        view
        returns (uint256 windowStart, uint256 calls, uint256 callsRemaining)
    {
        BotActivity storage activity = _botActivity[account];
        if (
            activity.windowStart == 0 ||
            block.timestamp >= activity.windowStart + BOT_WINDOW_SECONDS
        ) {
            return (block.timestamp, 0, BOT_MAX_CALLS_PER_WINDOW);
        }
        uint256 remaining = BOT_MAX_CALLS_PER_WINDOW - activity.calls;
        return (activity.windowStart, activity.calls, remaining);
    }
    uint256 private _entered = 1;
    modifier nonReentrant() {
        if (!(_entered == 1)) revert ETS1Error();
        _entered = 2;
        _;
        _entered = 1;
    }
    // =============================================================
    // CONTRACT STATE / EVENTS
    // =============================================================
    bool public paused;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Burn(address indexed account, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event ContentHashUpdated(bytes32 indexed oldHash, bytes32 indexed newHash);
    // =============================================================
    // ADDRESS BLOCKLIST
    // =============================================================
    mapping(address => bool) private _blocked;
    // Automatic anti-bot throttling: at most 5 protected calls per wallet
    // in each rolling 60-second window. These are fixed safety limits.
    uint256 public constant BOT_WINDOW_SECONDS = 60;
    uint256 public constant BOT_MAX_CALLS_PER_WINDOW = 5;
    struct BotActivity {
        uint256 windowStart;
        uint256 calls;
    }
    mapping(address => BotActivity) private _botActivity;
    event BotActivityThrottled(address indexed account, uint256 windowStart, uint256 calls);
    event AddressBlocked(address indexed account);
    event AddressUnblocked(address indexed account);
    function blockAddress(address account) external onlyOwner {
        _setAddressBlocked(account, true);
        emit AddressBlocked(account);
    }
    function unblockAddress(address account) external onlyOwner {
        _setAddressBlocked(account, false);
        emit AddressUnblocked(account);
    }
    function isBlocked(address account) external view returns (bool) {
        return _blocked[account];
    }
    // Bot controls use the existing owner-managed address blocklist.
    function blockBot(address account) external onlyOwner {
        _setAddressBlocked(account, true);
        emit AddressBlocked(account);
    }
    function unblockBot(address account) external onlyOwner {
        _setAddressBlocked(account, false);
        emit AddressUnblocked(account);
    }
    function isBotBlocked(address account) external view returns (bool) {
        return _blocked[account];
    }
    function _setAddressBlocked(address account, bool blocked) internal {
        if (!(account != address(0))) revert ETS1Error();
        if (blocked == _blocked[account]) revert ETS1Error();
        _blocked[account] = blocked;
    }
    // =============================================================
    // PERSONAL CIRCUIT BREAKER
    // =============================================================
    mapping(address => bool) public circuitBreakerEnabled;
    event PersonalCircuitBreakerEnabled(address indexed account);
    event PersonalCircuitBreakerDisabled(address indexed account);
    function enableCircuitBreaker() external notBlockedCaller {
        if (!(_balances[msg.sender] > 0)) revert ETS1Error();
        if (!(!circuitBreakerEnabled[msg.sender])) revert ETS1Error();
        circuitBreakerEnabled[msg.sender] = true;
        emit PersonalCircuitBreakerEnabled(msg.sender);
    }
    function disableCircuitBreaker() external notBlockedCaller {
        if (!(circuitBreakerEnabled[msg.sender])) revert ETS1Error();
        circuitBreakerEnabled[msg.sender] = false;
        emit PersonalCircuitBreakerDisabled(msg.sender);
    }
    // =============================================================
    // GLOBAL CIRCUIT BREAKER
    // =============================================================
    uint256 public circuitBreakerThreshold;
    uint256 public circuitBreakerWindow;
    uint256 public circuitBreakerLimit;
    bool public circuitBreakerTripped;
    mapping(address => uint256) private _cbWindowStart;
    mapping(address => uint256) private _cbWindowSpent;
    address public lastCircuitBreakerSender;
    event CircuitBreakerTriggered(address indexed from, address indexed to, uint256 amount);
    event CircuitBreakerThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event CircuitBreakerLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event CircuitBreakerWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event CircuitBreakerReset();
    event CircuitBreakerWalletWindowReset(address indexed account);
    function setCircuitBreaker(uint256 threshold, uint256 window, uint256 limit) external onlyOwner {
        emit CircuitBreakerThresholdUpdated(circuitBreakerThreshold, threshold);
        emit CircuitBreakerWindowUpdated(circuitBreakerWindow, window);
        emit CircuitBreakerLimitUpdated(circuitBreakerLimit, limit);
        circuitBreakerThreshold = threshold;
        circuitBreakerWindow = window;
        circuitBreakerLimit = limit;
    }
    function resetCircuitBreaker() external onlyOwner {
        if (!(circuitBreakerTripped)) revert ETS1Error();
        address offender = lastCircuitBreakerSender;
        if (offender != address(0)) {
            _cbWindowStart[offender] = 0;
            _cbWindowSpent[offender] = 0;
        }
        lastCircuitBreakerSender = address(0);
        circuitBreakerTripped = false;
        emit CircuitBreakerReset();
    }
    function resetCircuitBreakerWalletWindow(address account) external onlyOwner {
        if (!(account != address(0))) revert ETS1Error();
        _cbWindowStart[account] = 0;
        _cbWindowSpent[account] = 0;
        emit CircuitBreakerWalletWindowReset(account);
    }
    function circuitBreakerUsage(address account) external view returns (uint256 windowStart, uint256 spent) {
        return (_cbWindowStart[account], _cbWindowSpent[account]);
    }
    function _enforceCircuitBreaker(address from, address to, uint256 amount) internal returns (bool) {
        if (circuitBreakerThreshold > 0 && amount >= circuitBreakerThreshold) {
            _tripCircuitBreaker(from, to, amount);
            return false;
        }
        if (circuitBreakerLimit > 0 && circuitBreakerWindow > 0) {
            uint256 windowStart = _cbWindowStart[from];
            uint256 currentTime = block.timestamp;
            if (windowStart == 0 || currentTime >= windowStart + circuitBreakerWindow) {
                _cbWindowStart[from] = currentTime;
                _cbWindowSpent[from] = 0;
            }
            uint256 newSpent = _cbWindowSpent[from] + amount;
            if (newSpent > circuitBreakerLimit) {
                _tripCircuitBreaker(from, to, amount);
                return false;
            }
            _cbWindowSpent[from] = newSpent;
        }
        return true;
    }
    function _tripCircuitBreaker(address from, address to, uint256 amount) internal {
        circuitBreakerTripped = true;
        lastCircuitBreakerSender = from;
        if (!paused) {
            paused = true;
            emit Paused(msg.sender);
        }
        emit CircuitBreakerTriggered(from, to, amount);
    }
    // =============================================================
    // CUSTOM ACTION REGISTRY
    // =============================================================
    mapping(bytes32 => bool) private _actions;
    mapping(bytes32 => string) private _actionNames;
    event ActionRegistered(bytes32 indexed actionId, string actionName);
    event ActionRemoved(bytes32 indexed actionId);
    function registerAction(bytes32 actionId) external onlyOwner {
        _registerAction(actionId, "");
    }
    function registerAction(bytes32 actionId, string calldata actionName) external onlyOwner {
        _registerAction(actionId, actionName);
    }
    function _registerAction(bytes32 actionId, string memory actionName) internal {
        if (!(actionId != bytes32(0))) revert ETS1Error();
        if (!(!_actions[actionId])) revert ETS1Error();
        _actions[actionId] = true;
        _actionNames[actionId] = actionName;
        emit ActionRegistered(actionId, actionName);
    }
    function removeAction(bytes32 actionId) external onlyOwner {
        if (!(_actions[actionId])) revert ETS1Error();
        _actions[actionId] = false;
        delete _actionNames[actionId];
        emit ActionRemoved(actionId);
    }
    function isActionRegistered(bytes32 actionId) external view returns (bool) {
        return _actions[actionId];
    }
    function getActionName(bytes32 actionId) external view returns (string memory) {
        return _actionNames[actionId];
    }
    // =============================================================
    // ASSET TRACE LOGGING
    // =============================================================
    bytes32 public constant TRANSFER_ACTION = bytes32("TOKEN_TRANSFER");
    bytes32 public constant PURCHASE_ACTION = bytes32("TOKEN_PURCHASE");
    bytes32 public constant MANUAL_TRACE_ACTION = bytes32("MANUAL_ASSET_TRACE");
    struct AssetTrace {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        bytes32 actionId;
        bool manualRecord;
    }
    struct TransferDispute {
        uint256 traceId;
        address challenger;
        string reason;
        bool resolved;
        bool approved;
    }
    AssetTrace[] private _assetTraces;
    mapping(address => uint256[]) private _tracesByAddress;
    mapping(bytes32 => uint256[]) private _tracesByAction;
    TransferDispute[] private _transferDisputes;
    mapping(uint256 => uint256) private _disputeIdByTracePlusOne;
    event AssetTraced(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 indexed actionId,
        uint256 timestamp,
        bool manualRecord
    );
    event TransferChallenged(uint256 indexed disputeId, uint256 indexed traceId, address indexed challenger);
    event DisputeResolved(uint256 indexed disputeId, bool approved, uint256 recoveredAmount);
    function _recordAssetTrace(address from, address to, uint256 amount, bytes32 actionId, bool manualRecord)
        internal
    {
        uint256 traceIndex = _assetTraces.length;
        uint256 timestamp = block.timestamp;
        _assetTraces.push(AssetTrace(from, to, amount, timestamp, actionId, manualRecord));
        _tracesByAddress[from].push(traceIndex);
        if (to != from) _tracesByAddress[to].push(traceIndex);
        _tracesByAction[actionId].push(traceIndex);
        emit AssetTraced(from, to, amount, actionId, timestamp, manualRecord);
    }
    function logAssetTrace(address from, address to, uint256 amount, bytes32 actionId) external onlyOwner {
        if (!(from != address(0))) revert ETS1Error();
        if (!(to != address(0))) revert ETS1Error();
        if (!(_actions[actionId])) revert ETS1Error();
        _recordAssetTrace(from, to, amount, actionId, true);
    }
    function getAssetTraceCount() external view returns (uint256) {
        return _assetTraces.length;
    }
    function getAssetTrace(uint256 index) external view returns (AssetTrace memory) {
        if (!(index < _assetTraces.length)) revert ETS1Error();
        return _assetTraces[index];
    }
    function challengeTransfer(uint256 traceId, string calldata reason)
        external
        notBlockedCaller
        returns (uint256 disputeId)
    {
        if (!(traceId < _assetTraces.length)) revert ETS1Error();
        if (!(_assetTraces[traceId].actionId == TRANSFER_ACTION)) revert ETS1Error();
        if (!(_disputeIdByTracePlusOne[traceId] == 0)) revert ETS1Error();
        if (!(bytes(reason).length > 0)) revert ETS1Error();
        disputeId = _transferDisputes.length;
        _transferDisputes.push(TransferDispute(traceId, msg.sender, reason, false, false));
        _disputeIdByTracePlusOne[traceId] = disputeId + 1;
        emit TransferChallenged(disputeId, traceId, msg.sender);
    }
    function approveDispute(uint256 disputeId) external onlyOwner returns (uint256 recoveredAmount) {
        if (!(disputeId < _transferDisputes.length)) revert ETS1Error();
        TransferDispute storage dispute = _transferDisputes[disputeId];
        if (!(!dispute.resolved)) revert ETS1Error();
        AssetTrace storage trace = _assetTraces[dispute.traceId];
        recoveredAmount = _balances[trace.to] < trace.amount ? _balances[trace.to] : trace.amount;
        if (recoveredAmount > 0) {
            if (!(_transfer(trace.to, trace.from, recoveredAmount))) revert ETS1Error();
        }
        dispute.resolved = true;
        dispute.approved = true;
        emit DisputeResolved(disputeId, true, recoveredAmount);
    }
    function rejectDispute(uint256 disputeId) external onlyOwner {
        if (!(disputeId < _transferDisputes.length)) revert ETS1Error();
        TransferDispute storage dispute = _transferDisputes[disputeId];
        if (!(!dispute.resolved)) revert ETS1Error();
        dispute.resolved = true;
        dispute.approved = false;
        emit DisputeResolved(disputeId, false, 0);
    }
    function getDispute(uint256 disputeId) external view returns (TransferDispute memory) {
        if (!(disputeId < _transferDisputes.length)) revert ETS1Error();
        return _transferDisputes[disputeId];
    }
    function getAssetTracesForAddress(address account) external view returns (AssetTrace[] memory result) {
        uint256[] storage indexes = _tracesByAddress[account];
        result = new AssetTrace[](indexes.length);
        for (uint256 i; i < indexes.length; i++) result[i] = _assetTraces[indexes[i]];
    }
    function getAssetTracesForAddressPaginated(address account, uint256 offset, uint256 limit)
        external
        view
        returns (AssetTrace[] memory result)
    {
        uint256[] storage indexes = _tracesByAddress[account];
        if (!(offset <= indexes.length)) revert ETS1Error();
        uint256 remaining = indexes.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new AssetTrace[](count);
        for (uint256 i; i < count; i++) result[i] = _assetTraces[indexes[offset + i]];
    }
    function getAssetTracesByAction(bytes32 actionId) external view returns (AssetTrace[] memory result) {
        uint256[] storage indexes = _tracesByAction[actionId];
        result = new AssetTrace[](indexes.length);
        for (uint256 i; i < indexes.length; i++) result[i] = _assetTraces[indexes[i]];
    }
    function getAssetTracesByActionPaginated(bytes32 actionId, uint256 offset, uint256 limit)
        external
        view
        returns (AssetTrace[] memory result)
    {
        uint256[] storage indexes = _tracesByAction[actionId];
        if (!(offset <= indexes.length)) revert ETS1Error();
        uint256 remaining = indexes.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new AssetTrace[](count);
        for (uint256 i; i < count; i++) result[i] = _assetTraces[indexes[offset + i]];
    }
    function getAssetTracesPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (AssetTrace[] memory result)
    {
        if (!(offset <= _assetTraces.length)) revert ETS1Error();
        uint256 remaining = _assetTraces.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new AssetTrace[](count);
        for (uint256 i; i < count; i++) result[i] = _assetTraces[offset + i];
    }
    function getTraceableAssetHistory(address account)
        external
        view
        returns (
            address[] memory from,
            address[] memory to,
            uint256[] memory amounts,
            uint256[] memory timestamps,
            bytes32[] memory actionIds
        )
    {
        uint256[] storage indexes = _tracesByAddress[account];
        uint256 count = indexes.length;
        from = new address[](count);
        to = new address[](count);
        amounts = new uint256[](count);
        timestamps = new uint256[](count);
        actionIds = new bytes32[](count);
        for (uint256 i; i < count; i++) {
            AssetTrace storage trace = _assetTraces[indexes[i]];
            from[i] = trace.from;
            to[i] = trace.to;
            amounts[i] = trace.amount;
            timestamps[i] = trace.timestamp;
            actionIds[i] = trace.actionId;
        }
    }
    function getTracedVolumeForAddress(address account) external view returns (uint256 sent, uint256 received) {
        uint256[] storage indexes = _tracesByAddress[account];
        for (uint256 i; i < indexes.length; i++) {
            AssetTrace storage trace = _assetTraces[indexes[i]];
            if (trace.from == account) sent += trace.amount;
            if (trace.to == account) received += trace.amount;
        }
    }
    // =============================================================
    // PURCHASE CONFIGURATION / HISTORY
    // =============================================================
    address public usdcToken;
    uint8 public usdcDecimals;
    address public nativeUsdPriceFeed;
    uint8 public nativeUsdFeedDecimals;
    uint256 public nativePriceMaxAge;
    struct PurchaseRecord {
        address buyer;
        address paymentAsset; // address(0) means native network currency
        uint256 eonsAmount;
        uint256 paymentAmount;
        uint256 timestamp;
    }
    PurchaseRecord[] private _purchases;
    mapping(address => uint256[]) private _purchasesByBuyer;
    mapping(address => uint256) public nativeRefundCredit;
    event USDCConfigured(address indexed token, uint8 decimals);
    event NativePriceFeedConfigured(address indexed feed, uint8 decimals, uint256 maxAge);
    event EONSPurchased(
        address indexed buyer,
        address indexed paymentAsset,
        uint256 eonsAmount,
        uint256 paymentAmount,
        uint256 indexed purchaseId
    );
    event NativeRefundCredited(address indexed account, uint256 amount);
    event NativeRefundWithdrawn(address indexed account, uint256 amount);
    event SalesInventoryDeposited(uint256 amount);
    event SalesInventoryWithdrawn(address indexed recipient, uint256 amount);
    event USDCProceedsWithdrawn(address indexed recipient, uint256 amount);
    event NativeProceedsWithdrawn(address indexed recipient, uint256 amount);
    // =============================================================
    // CONSTRUCTOR
    // =============================================================
    constructor() {
        address initialOwner = msg.sender;
        if (!(initialOwner != address(0))) revert ETS1Error();
        _owner = initialOwner;
        _totalSupply = TOTAL_SUPPLY;
        _balances[initialOwner] = TOTAL_SUPPLY - INITIAL_SALES_INVENTORY;
        _balances[address(this)] = INITIAL_SALES_INVENTORY;
        emit OwnershipTransferred(address(0), initialOwner);
        emit Transfer(address(0), initialOwner, _balances[initialOwner]);
        emit Transfer(address(0), address(this), INITIAL_SALES_INVENTORY);
    }
    // =============================================================
    // TOKEN FUNCTIONS
    // =============================================================
    // =============================================================
    // ERC-20 METADATA
    // =============================================================
    function burn(uint256 amount) external notBlockedCaller notPaused returns (bool) {
        if (!(_balances[msg.sender] >= amount)) revert ETS1Error();
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        burnedAmount[msg.sender] += amount;
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
        return true;
    }
    function name() external pure returns (string memory) {
        return "EONS";
    }
    function symbol() external pure returns (string memory) {
        return "E";
    }
    function decimals() external pure returns (uint8) {
        return 18;
    }
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    function circulatingSupply() external view returns (uint256) {
        return _totalSupply - _balances[address(this)];
    }
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    function isHolder(address account) external view returns (bool) {
        return _balances[account] > 0;
    }
    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }
    function transfer(address to, uint256 amount) external automaticBotThrottle notPaused returns (bool) {
        return _transfer(msg.sender, to, amount);
    }
    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts)
        external
        notBlockedCaller
        automaticBotThrottle
        notPaused
        returns (bool)
    {
        if (!(recipients.length == amounts.length)) revert ETS1Error();
        for (uint256 i = 0; i < recipients.length; i++) {
            if (!_transfer(msg.sender, recipients[i], amounts[i])) return false;
        }
        return true;
    }
    function approve(address spender, uint256 amount) external notBlockedCaller notPaused returns (bool) {
        if (!(spender != address(0))) revert ETS1Error();
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) external notBlockedCaller notPaused returns (bool) {
        if (!(spender != address(0))) revert ETS1Error();
        uint256 newAllowance = _allowances[msg.sender][spender] + addedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external notBlockedCaller notPaused returns (bool) {
        if (!(spender != address(0))) revert ETS1Error();
        uint256 currentAllowance = _allowances[msg.sender][spender];
        if (!(currentAllowance >= subtractedValue)) revert ETS1Error();
        uint256 newAllowance = currentAllowance - subtractedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external automaticBotThrottle notPaused returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (!(currentAllowance >= amount)) revert ETS1Error();
        bool transferred = _transfer(from, to, amount);
        if (!transferred) return false;
        _allowances[from][msg.sender] = currentAllowance - amount;
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        return true;
    }
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        if (!(from != address(0))) revert ETS1Error();
        if (!(to != address(0))) revert ETS1Error();
        if (!(!_blocked[from])) revert ETS1Error();
        if (!(!_blocked[to])) revert ETS1Error();
        if (!(!circuitBreakerEnabled[from])) revert ETS1Error();
        if (!(_balances[from] >= amount)) revert ETS1Error();
        if (!_enforceCircuitBreaker(from, to, amount)) return false;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        _recordAssetTrace(from, to, amount, TRANSFER_ACTION, false);
        return true;
    }
    // =============================================================
    // PURCHASE CONFIGURATION
    // =============================================================
    function configureUSDC(address token) external onlyOwner {
        if (!(token != address(0))) revert ETS1Error();
        try IETS1(token).decimals() returns (uint8 tokenDecimals) {
            if (!(tokenDecimals > 0 && tokenDecimals <= 18)) revert ETS1Error();
            usdcToken = token;
            usdcDecimals = tokenDecimals;
            emit USDCConfigured(token, tokenDecimals);
        } catch {
            revert ETS1Error();
        }
    }
    function configureNativePriceFeed(address feed, uint256 maxAge) external onlyOwner {
        if (!(feed != address(0))) revert ETS1Error();
        if (!(maxAge > 0)) revert ETS1Error();
        try IETS1PriceFeed(feed).decimals() returns (uint8 feedDecimals) {
            if (!(feedDecimals <= 18)) revert ETS1Error();
            nativeUsdPriceFeed = feed;
            nativeUsdFeedDecimals = feedDecimals;
            nativePriceMaxAge = maxAge;
            emit NativePriceFeedConfigured(feed, feedDecimals, maxAge);
        } catch {
            revert ETS1Error();
        }
    }
    function usdcCostForEons(uint256 eonsAmount) public view returns (uint256) {
        if (!(usdcToken != address(0))) revert ETS1Error();
        uint256 scale = 10 ** uint256(usdcDecimals);
        uint256 numerator = eonsAmount * USDC_PRICE_PER_EONS * scale;
        // Round up so fractional EONS cannot be purchased for zero/underpaid USDC.
        return (numerator + TOKEN_UNIT - 1) / TOKEN_UNIT;
    }
    function quoteNativeForEons(uint256 eonsAmount) public view returns (uint256) {
        if (!(nativeUsdPriceFeed != address(0))) revert ETS1Error();
        uint256 usdcCost = usdcCostForEons(eonsAmount);
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IETS1PriceFeed(nativeUsdPriceFeed).latestRoundData();
        if (!(answer > 0)) revert ETS1Error();
        if (!(updatedAt != 0 && updatedAt <= block.timestamp)) revert ETS1Error();
        if (!(block.timestamp - updatedAt <= nativePriceMaxAge)) revert ETS1Error();
        if (!(answeredInRound >= roundId)) revert ETS1Error();
        // USDC base units -> USD -> native currency wei.
        uint256 exponent = uint256(nativeUsdFeedDecimals) + 18 - uint256(usdcDecimals);
        uint256 numerator = usdcCost * (10 ** exponent);
        uint256 price = uint256(answer);
        return (numerator + price - 1) / price;
    }
    function salesInventory() public view returns (uint256) {
        return _balances[address(this)];
    }
    function depositSalesInventory(uint256 amount)
        external
        notBlockedCaller
        automaticBotThrottle
        notPaused
        returns (bool)
    {
        if (!(amount > 0)) revert ETS1Error();
        bool moved = _transfer(msg.sender, address(this), amount);
        if (moved) emit SalesInventoryDeposited(amount);
        return moved;
    }
    function withdrawSalesInventory(uint256 amount, address recipient)
        external
        onlyOwner
        notPaused
        returns (bool)
    {
        if (!(recipient != address(0))) revert ETS1Error();
        if (!(amount > 0)) revert ETS1Error();
        bool moved = _transfer(address(this), recipient, amount);
        if (moved) emit SalesInventoryWithdrawn(recipient, amount);
        return moved;
    }
    function withdrawUSDCProceeds(address recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
        returns (bool)
    {
        if (!(recipient != address(0))) revert ETS1Error();
        if (!(amount > 0)) revert ETS1Error();
        if (!(usdcToken != address(0))) revert ETS1Error();
        _safeTokenTransfer(usdcToken, recipient, amount);
        emit USDCProceedsWithdrawn(recipient, amount);
        return true;
    }
    function withdrawNativeProceeds(address payable recipient, uint256 amount)
        external
        onlyOwner
        nonReentrant
        returns (bool)
    {
        if (!(recipient != address(0))) revert ETS1Error();
        if (!(amount > 0)) revert ETS1Error();
        if (!(address(this).balance >= amount)) revert ETS1Error();
        _sendNative(recipient, amount);
        emit NativeProceedsWithdrawn(recipient, amount);
        return true;
    }
    function buyWithUSDC(uint256 eonsAmount)
        external
        notBlockedCaller
        automaticBotThrottle
        notPaused
        nonReentrant
        returns (bool)
    {
        if (!(eonsAmount > 0)) revert ETS1Error();
        if (!(usdcToken != address(0))) revert ETS1Error();
        uint256 paymentAmount = usdcCostForEons(eonsAmount);
        if (!(_balances[address(this)] >= eonsAmount)) revert ETS1Error();
        // Move tokens first. If the breaker trips, no payment is collected.
        if (!_transfer(address(this), msg.sender, eonsAmount)) return false;
        uint256 balanceBefore = IETS1(usdcToken).balanceOf(address(this));
        _safeTokenTransferFrom(usdcToken, msg.sender, address(this), paymentAmount);
        uint256 balanceAfter = IETS1(usdcToken).balanceOf(address(this));
        if (!(balanceAfter - balanceBefore == paymentAmount)) revert ETS1Error();
        _recordPurchase(msg.sender, usdcToken, eonsAmount, paymentAmount);
        return true;
    }
    function buyWithNative(uint256 eonsAmount, uint256 maxNativePayment)
        external
        payable
        notBlockedCaller
        automaticBotThrottle
        notPaused
        nonReentrant
        returns (bool)
    {
        if (!(eonsAmount > 0)) revert ETS1Error();
        if (!(_balances[address(this)] >= eonsAmount)) revert ETS1Error();
        uint256 paymentAmount = quoteNativeForEons(eonsAmount);
        if (!(paymentAmount <= maxNativePayment)) revert ETS1Error();
        if (!(msg.value >= paymentAmount)) revert ETS1Error();
        if (!_transfer(address(this), msg.sender, eonsAmount)) {
            nativeRefundCredit[msg.sender] += msg.value;
            emit NativeRefundCredited(msg.sender, msg.value);
            return false;
        }
        _recordPurchase(
            msg.sender,
            address(0),
            eonsAmount,
            paymentAmount
        );
        uint256 excess = msg.value - paymentAmount;
        if (excess > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: excess}("");
            if (!refunded) {
                nativeRefundCredit[msg.sender] += excess;
                emit NativeRefundCredited(msg.sender, excess);
            }
        }
        return true;
    }
    function withdrawNativeRefund() external notBlockedCaller nonReentrant {
        uint256 amount = nativeRefundCredit[msg.sender];
        if (!(amount > 0)) revert ETS1Error();
        nativeRefundCredit[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!(success)) revert ETS1Error();
        emit NativeRefundWithdrawn(msg.sender, amount);
    }
    function _sendNative(address recipient, uint256 amount) internal {
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!(success)) revert ETS1Error();
    }
    function _safeTokenTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IETS1.transfer.selector, to, amount));
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) revert ETS1Error();
    }
    function _safeTokenTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IETS1.transferFrom.selector, from, to, amount));
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) revert ETS1Error();
    }
    function _recordPurchase(
        address buyer,
        address paymentAsset,
        uint256 eonsAmount,
        uint256 paymentAmount
    ) internal {
        uint256 purchaseId = _purchases.length;
        _purchases.push(
            PurchaseRecord(
                buyer,
                paymentAsset,
                eonsAmount,
                paymentAmount,
                block.timestamp
            )
        );
        _purchasesByBuyer[buyer].push(purchaseId);
        emit EONSPurchased(
            buyer,
            paymentAsset,
            eonsAmount,
            paymentAmount,
            purchaseId
        );
        _recordAssetTrace(address(0), buyer, eonsAmount, PURCHASE_ACTION, false);
    }
    function getPurchaseCount() external view returns (uint256) {
        return _purchases.length;
    }
    function getPurchase(uint256 index) external view returns (PurchaseRecord memory) {
        if (!(index < _purchases.length)) revert ETS1Error();
        return _purchases[index];
    }
    function getPurchasesPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (PurchaseRecord[] memory result)
    {
        if (!(offset <= _purchases.length)) revert ETS1Error();
        uint256 remaining = _purchases.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new PurchaseRecord[](count);
        for (uint256 i; i < count; i++) result[i] = _purchases[offset + i];
    }
    function getPurchasesForBuyer(address buyer) external view returns (PurchaseRecord[] memory result) {
        uint256[] storage indexes = _purchasesByBuyer[buyer];
        result = new PurchaseRecord[](indexes.length);
        for (uint256 i; i < indexes.length; i++) result[i] = _purchases[indexes[i]];
    }
    function getPurchasesForBuyerPaginated(address buyer, uint256 offset, uint256 limit)
        external
        view
        returns (PurchaseRecord[] memory result)
    {
        uint256[] storage indexes = _purchasesByBuyer[buyer];
        if (!(offset <= indexes.length)) revert ETS1Error();
        uint256 remaining = indexes.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new PurchaseRecord[](count);
        for (uint256 i; i < count; i++) result[i] = _purchases[indexes[offset + i]];
    }
    // =============================================================
    // OWNER / PAUSE FUNCTIONS
    // =============================================================
    function owner() external view returns (address) {
        return _owner;
    }
    function transferOwnership(address newOwner) external onlyOwner {
        if (!(newOwner != address(0))) revert ETS1Error();
        if (!(newOwner != _owner)) revert ETS1Error();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }
    function acceptOwnership() external {
        if (!(msg.sender == pendingOwner)) revert ETS1Error();
        address previousOwner = _owner;
        _owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }
    function renounceOwnership() external onlyOwner {
        if (!(!paused && !circuitBreakerTripped)) revert ETS1Error();
        if (!(pendingOwner == address(0))) revert ETS1Error();
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }
    function pause() external onlyOwner {
        if (!(!paused)) revert ETS1Error();
        paused = true;
        emit Paused(msg.sender);
    }
    function unpause() external onlyOwner {
        if (!(paused)) revert ETS1Error();
        if (!(!circuitBreakerTripped)) revert ETS1Error();
        paused = false;
        emit Unpaused(msg.sender);
    }
    function setContentHash(bytes32 newHash) external onlyOwner {
        emit ContentHashUpdated(contentHash, newHash);
        contentHash = newHash;
    }
}
import BN from 'bn.js'
import { Buffer } from 'buffer'
import createKeccakHash from 'keccak'
function CORE1 (value: Buffer | BN | string | number) {
  value = toBuffer(value)
  return createKeccakHash('keccak256').update(value as Buffer).digest()
}
function toBuffer (value: any) {
  if (!Buffer.isBuffer(value)) {
    if (Array.isArray(value)) {
      value = Buffer.from(value)
    } else if (typeof value === 'string') {
      if (isHexString(value)) {
        value = Buffer.from(padToEven(stripHexPrefix(value)), 'hex')
      } else {
        value = Buffer.from(value)
      }
    } else if (typeof value === 'number') {
      value = intToBuffer(value)
    } else if (value === null || value === undefined) {
      value = Buffer.allocUnsafe(0)
    } else if (BN.isBN(value)) {
      value = value.toArrayLike(Buffer)
    } else if (value.toArray) {
      value = Buffer.from(value.toArray())
    } else {
      throw new Error('invalid type')
    }
  }
  return value
}
function isHexString (value: any, length?: number) {
  if (typeof value !== 'string' || !value.match(/^0x[0-9A-Fa-f]*$/)) {
    return false
  }
  if (length && value.length !== 2 + 2 * length) {
    return false
  }
  return true
}
function padToEven (value: any) {
  if (typeof value !== 'string') {
    throw new Error(`while padding to even, value must be string, is currently ${typeof value}, while padToEven.`)
  }
  if (value.length % 2) {
    value = `0${value}`
  }
  return value
}
function stripHexPrefix (value: any) {
  if (typeof value !== 'string') {
    return value
  }
  return isHexPrefixed(value) ? value.slice(2) : value
}
function isHexPrefixed (value: any) {
  if (typeof value !== 'string') {
    throw new Error("value must be type 'string', is currently type " + (typeof value) + ', while checking isHexPrefixed.')
  }
  return value.slice(0, 2) === '0x'
}
function intToBuffer (i: number) {
  const hex = intToHex(i)
  return Buffer.from(padToEven(hex.slice(2)), 'hex')
}
function intToHex (i: number) {
  const hex = i.toString(16)
  return `0x${hex}`
}
if (typeof window !== 'undefined') {
  (window as any).CORE1 = CORE1
}
export = CORE1
