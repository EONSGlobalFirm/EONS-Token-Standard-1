// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

/**
 * @title ETS-1 — EONS Token Standard 1 is a Universal Fungible Token Standard With Customizable Actions
 * @author Katascha White (Katascha.White@outlook.com) @dev yahoo handle since 2003
 *EONS GLOBAL FIRM CONTRACT
 * @notice
 * ETS-1 is a fixed-supply ETS-1-compatible fungible token
 * standard for the EONS (E) token.
 *
 * Features:
 * - Fixed supply of 100 billion E
 * - Entire supply created during deployment
 * - Transferable Ownership with acceptance
 * - No minting after deployment
 * - Owner/controller identification
 * - Emergency Global pause mechanism
 * - Circuit breaker (auto-pause on large or rate-limited transfers)access for all token holders
 * - Customizable action registry
 * - Beneficiary registry
 * - Asset trace history/logging
 */

interface IERC20 {
   function totalSupply() external view returns (uint256);
   function balanceOf(address account) external view returns (uint256);
   function transfer(address recipient, uint256 amount) external returns (bool);
   function allowance(address owner, address spender) external view returns (uint256);
   function approve(address spender, uint256 amount) external returns (bool);
   function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

   event Transfer(address indexed from, address indexed to, uint256 value);
   event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
   function name() external view returns (string memory);
   function symbol() external view returns (string memory);
   function decimals() external view returns (uint8);
}

interface IETS1ERC20 {
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
     * - Beneficiary System
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
     * - Beneficiary Management
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
    uint256 private _totalSupply;

    // Purchase price: 2 USDC for 1 whole EONS.
    uint256 public constant USDC_PRICE_PER_EONS = 2;
    uint256 private constant TOKEN_UNIT = 10 ** 18;

    // User-supplied Eons Global Foundation wallet.
    address public constant INITIAL_EONS_FOUNDATION_WALLET =
        address(uint160(0x98B47DB768Ae6E85130EBF26683B1e31080510cb));

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
        require(msg.sender == _owner, "ETS-1: Not authorized");
        _;
    }

    modifier notPaused() {
        require(!paused, "ETS-1: Contract paused");
        _;
    }

    uint256 private _entered = 1;
    modifier nonReentrant() {
        require(_entered == 1, "ETS-1: Reentrant call");
        _entered = 2;
        _;
        _entered = 1;
    }

    // =============================================================
    // BENEFICIARIES
    // =============================================================

    struct Beneficiary {
        string name;
        uint256 percentage;
        address wallet;
    }

    Beneficiary[2] private _beneficiaries;

    event BeneficiaryWalletUpdated(uint256 indexed index, address indexed oldWallet, address indexed newWallet);
    event BeneficiaryDistribution(uint256 kataschaAmount, uint256 foundationAmount, address paymentAsset);

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

    event AddressBlocked(address indexed account);
    event AddressUnblocked(address indexed account);

    function blockAddress(address account) external onlyOwner {
        require(account != address(0), "ETS-1: Invalid address");
        require(!_blocked[account], "ETS-1: Address already blocked");
        _blocked[account] = true;
        emit AddressBlocked(account);
    }

    function unblockAddress(address account) external onlyOwner {
        require(_blocked[account], "ETS-1: Address not blocked");
        _blocked[account] = false;
        emit AddressUnblocked(account);
    }

    function isBlocked(address account) external view returns (bool) {
        return _blocked[account];
    }

    // =============================================================
    // PERSONAL CIRCUIT BREAKER
    // =============================================================

    mapping(address => bool) public circuitBreakerEnabled;

    event PersonalCircuitBreakerEnabled(address indexed account);
    event PersonalCircuitBreakerDisabled(address indexed account);

    function enableCircuitBreaker() external {
        require(_balances[msg.sender] > 0, "ETS-1: No EONS tokens");
        require(!circuitBreakerEnabled[msg.sender], "ETS-1: Already enabled");
        circuitBreakerEnabled[msg.sender] = true;
        emit PersonalCircuitBreakerEnabled(msg.sender);
    }

    function disableCircuitBreaker() external {
        require(circuitBreakerEnabled[msg.sender], "ETS-1: Not enabled");
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
        require(circuitBreakerTripped, "ETS-1: Circuit breaker not tripped");
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
        require(account != address(0), "ETS-1: Invalid address");
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
        require(actionId != bytes32(0), "ETS-1: Invalid action ID");
        require(!_actions[actionId], "ETS-1: Action already registered");
        _actions[actionId] = true;
        _actionNames[actionId] = actionName;
        emit ActionRegistered(actionId, actionName);
    }

    function removeAction(bytes32 actionId) external onlyOwner {
        require(_actions[actionId], "ETS-1: Action not registered");
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

    bytes32 public constant TRANSFER_ACTION = keccak256("TOKEN_TRANSFER");
    bytes32 public constant PURCHASE_ACTION = keccak256("TOKEN_PURCHASE");
    bytes32 public constant MANUAL_TRACE_ACTION = keccak256("MANUAL_ASSET_TRACE");

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
        require(from != address(0), "ETS-1: Invalid trace sender");
        require(to != address(0), "ETS-1: Invalid trace receiver");
        require(_actions[actionId], "ETS-1: Action not registered");
        _recordAssetTrace(from, to, amount, actionId, true);
    }

    function getAssetTraceCount() external view returns (uint256) {
        return _assetTraces.length;
    }

    function getAssetTrace(uint256 index) external view returns (AssetTrace memory) {
        require(index < _assetTraces.length, "ETS-1: Invalid trace index");
        return _assetTraces[index];
    }

    function challengeTransfer(uint256 traceId, string calldata reason)
        external
        returns (uint256 disputeId)
    {
        require(traceId < _assetTraces.length, "ETS-1: Invalid trace index");
        require(_assetTraces[traceId].actionId == TRANSFER_ACTION, "ETS-1: Trace is not a transfer");
        require(_disputeIdByTracePlusOne[traceId] == 0, "ETS-1: Transfer already challenged");
        require(bytes(reason).length > 0, "ETS-1: Empty dispute reason");

        disputeId = _transferDisputes.length;
        _transferDisputes.push(TransferDispute(traceId, msg.sender, reason, false, false));
        _disputeIdByTracePlusOne[traceId] = disputeId + 1;
        emit TransferChallenged(disputeId, traceId, msg.sender);
    }

    function approveDispute(uint256 disputeId) external onlyOwner returns (uint256 recoveredAmount) {
        require(disputeId < _transferDisputes.length, "ETS-1: Invalid dispute ID");
        TransferDispute storage dispute = _transferDisputes[disputeId];
        require(!dispute.resolved, "ETS-1: Dispute already resolved");

        AssetTrace storage trace = _assetTraces[dispute.traceId];
        recoveredAmount = _balances[trace.to] < trace.amount ? _balances[trace.to] : trace.amount;
        if (recoveredAmount > 0) {
            require(_transfer(trace.to, trace.from, recoveredAmount), "ETS-1: Recovery blocked");
        }

        dispute.resolved = true;
        dispute.approved = true;
        emit DisputeResolved(disputeId, true, recoveredAmount);
    }

    function rejectDispute(uint256 disputeId) external onlyOwner {
        require(disputeId < _transferDisputes.length, "ETS-1: Invalid dispute ID");
        TransferDispute storage dispute = _transferDisputes[disputeId];
        require(!dispute.resolved, "ETS-1: Dispute already resolved");

        dispute.resolved = true;
        dispute.approved = false;
        emit DisputeResolved(disputeId, false, 0);
    }

    function getDispute(uint256 disputeId) external view returns (TransferDispute memory) {
        require(disputeId < _transferDisputes.length, "ETS-1: Invalid dispute ID");
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
        require(offset <= indexes.length, "ETS-1: Offset out of range");
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
        require(offset <= indexes.length, "ETS-1: Offset out of range");
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
        require(offset <= _assetTraces.length, "ETS-1: Offset out of range");
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
        uint256 kataschaPayment;
        uint256 foundationPayment;
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
        uint256 kataschaPayment,
        uint256 foundationPayment,
        uint256 indexed purchaseId
    );
    event NativeRefundCredited(address indexed account, uint256 amount);
    event NativeRefundWithdrawn(address indexed account, uint256 amount);
    event SalesInventoryDeposited(uint256 amount);
    event SalesInventoryWithdrawn(address indexed recipient, uint256 amount);

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    constructor(address kataschaWallet) {
        address initialOwner = msg.sender;
        require(initialOwner != address(0), "ETS-1: Invalid owner");
        require(kataschaWallet != address(0), "ETS-1: Invalid Katascha wallet");

        _owner = initialOwner;
        _totalSupply = TOTAL_SUPPLY;
        _balances[initialOwner] = TOTAL_SUPPLY;

        _beneficiaries[0] = Beneficiary("Katascha White", 35, kataschaWallet);
        _beneficiaries[1] = Beneficiary(
            "Eons Global Foundation",
            65,
            INITIAL_EONS_FOUNDATION_WALLET
        );

        require(
            _beneficiaries[0].percentage + _beneficiaries[1].percentage == 100,
            "ETS-1: Beneficiary total must equal 100"
        );

        emit OwnershipTransferred(address(0), initialOwner);
        emit Transfer(address(0), initialOwner, TOTAL_SUPPLY);
    }

    // =============================================================
    // TOKEN FUNCTIONS
    // =============================================================

    // =============================================================
    // ERC-20 METADATA
    // =============================================================

    function burn(uint256 amount) external notPaused returns (bool) {
        require(_balances[msg.sender] >= amount, "ETS-1: Insufficient balance");
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

    function transfer(address to, uint256 amount) external notPaused returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts)
        external
        notPaused
        returns (bool)
    {
        require(recipients.length == amounts.length, "ETS-1: Array mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            if (!_transfer(msg.sender, recipients[i], amounts[i])) return false;
        }
        return true;
    }

    function approve(address spender, uint256 amount) external notPaused returns (bool) {
        require(spender != address(0), "ETS-1: Invalid spender");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external notPaused returns (bool) {
        require(spender != address(0), "ETS-1: Invalid spender");
        uint256 newAllowance = _allowances[msg.sender][spender] + addedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external notPaused returns (bool) {
        require(spender != address(0), "ETS-1: Invalid spender");
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ETS-1: Allowance below zero");
        uint256 newAllowance = currentAllowance - subtractedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external notPaused returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ETS-1: Insufficient allowance");

        bool transferred = _transfer(from, to, amount);
        if (!transferred) return false;

        _allowances[from][msg.sender] = currentAllowance - amount;
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(from != address(0), "ETS-1: Invalid sender");
        require(to != address(0), "ETS-1: Invalid receiver");
        require(!_blocked[from], "ETS-1: Sender is blocked");
        require(!_blocked[to], "ETS-1: Receiver is blocked");
        require(!circuitBreakerEnabled[from], "ETS-1: Sender wallet circuit breaker enabled");
        require(_balances[from] >= amount, "ETS-1: Insufficient balance");

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
        require(token != address(0), "ETS-1: Invalid USDC address");
        try IETS1ERC20(token).decimals() returns (uint8 tokenDecimals) {
            require(tokenDecimals > 0 && tokenDecimals <= 18, "ETS-1: Unsupported USDC decimals");
            usdcToken = token;
            usdcDecimals = tokenDecimals;
            emit USDCConfigured(token, tokenDecimals);
        } catch {
            revert("ETS-1: Cannot read USDC decimals");
        }
    }

    function configureNativePriceFeed(address feed, uint256 maxAge) external onlyOwner {
        require(feed != address(0), "ETS-1: Invalid price feed");
        require(maxAge > 0, "ETS-1: Invalid price age");
        try IETS1PriceFeed(feed).decimals() returns (uint8 feedDecimals) {
            require(feedDecimals <= 18, "ETS-1: Unsupported feed decimals");
            nativeUsdPriceFeed = feed;
            nativeUsdFeedDecimals = feedDecimals;
            nativePriceMaxAge = maxAge;
            emit NativePriceFeedConfigured(feed, feedDecimals, maxAge);
        } catch {
            revert("ETS-1: Cannot read feed decimals");
        }
    }

    function usdcCostForEons(uint256 eonsAmount) public view returns (uint256) {
        require(usdcToken != address(0), "ETS-1: USDC not configured");
        uint256 scale = 10 ** uint256(usdcDecimals);
        uint256 numerator = eonsAmount * USDC_PRICE_PER_EONS * scale;
        // Round up so fractional EONS cannot be purchased for zero/underpaid USDC.
        return (numerator + TOKEN_UNIT - 1) / TOKEN_UNIT;
    }

    function quoteNativeForEons(uint256 eonsAmount) public view returns (uint256) {
        require(nativeUsdPriceFeed != address(0), "ETS-1: Native price feed not configured");
        uint256 usdcCost = usdcCostForEons(eonsAmount);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IETS1PriceFeed(nativeUsdPriceFeed).latestRoundData();

        require(answer > 0, "ETS-1: Invalid oracle price");
        require(updatedAt != 0 && updatedAt <= block.timestamp, "ETS-1: Invalid oracle timestamp");
        require(block.timestamp - updatedAt <= nativePriceMaxAge, "ETS-1: Stale oracle price");
        require(answeredInRound >= roundId, "ETS-1: Incomplete oracle round");

        // USDC base units -> USD -> native currency wei.
        uint256 exponent = uint256(nativeUsdFeedDecimals) + 18 - uint256(usdcDecimals);
        uint256 numerator = usdcCost * (10 ** exponent);
        uint256 price = uint256(answer);
        return (numerator + price - 1) / price;
    }

    function salesInventory() public view returns (uint256) {
        return _balances[address(this)];
    }

    function depositSalesInventory(uint256 amount) external notPaused returns (bool) {
        require(amount > 0, "ETS-1: Zero inventory deposit");
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
        require(recipient != address(0), "ETS-1: Invalid recipient");
        require(amount > 0, "ETS-1: Zero inventory withdrawal");
        bool moved = _transfer(address(this), recipient, amount);
        if (moved) emit SalesInventoryWithdrawn(recipient, amount);
        return moved;
    }

    function buyWithUSDC(uint256 eonsAmount) external notPaused nonReentrant returns (bool) {
        require(eonsAmount > 0, "ETS-1: Zero purchase");
        require(usdcToken != address(0), "ETS-1: USDC not configured");
        uint256 paymentAmount = usdcCostForEons(eonsAmount);
        require(_balances[address(this)] >= eonsAmount, "ETS-1: Insufficient sales inventory");

        // Move tokens first. If the breaker trips, no payment is collected.
        if (!_transfer(address(this), msg.sender, eonsAmount)) return false;

        uint256 balanceBefore = IETS1ERC20(usdcToken).balanceOf(address(this));
        _safeTokenTransferFrom(usdcToken, msg.sender, address(this), paymentAmount);
        uint256 balanceAfter = IETS1ERC20(usdcToken).balanceOf(address(this));
        require(balanceAfter - balanceBefore == paymentAmount, "ETS-1: Fee-on-transfer USDC unsupported");

        (uint256 kataschaAmount, uint256 foundationAmount) = _splitPayment(paymentAmount);
        _safeTokenTransfer(usdcToken, _beneficiaries[0].wallet, kataschaAmount);
        _safeTokenTransfer(usdcToken, _beneficiaries[1].wallet, foundationAmount);

        _recordPurchase(msg.sender, usdcToken, eonsAmount, paymentAmount, kataschaAmount, foundationAmount);
        emit BeneficiaryDistribution(kataschaAmount, foundationAmount, usdcToken);
        return true;
    }

    function buyWithNative(uint256 eonsAmount, uint256 maxNativePayment)
        external
        payable
        notPaused
        nonReentrant
        returns (bool)
    {
        require(eonsAmount > 0, "ETS-1: Zero purchase");
        require(_balances[address(this)] >= eonsAmount, "ETS-1: Insufficient sales inventory");

        uint256 paymentAmount = quoteNativeForEons(eonsAmount);
        require(paymentAmount <= maxNativePayment, "ETS-1: Native quote exceeds maximum");
        require(msg.value >= paymentAmount, "ETS-1: Insufficient native payment");

        if (!_transfer(address(this), msg.sender, eonsAmount)) {
            nativeRefundCredit[msg.sender] += msg.value;
            emit NativeRefundCredited(msg.sender, msg.value);
            return false;
        }

        (uint256 kataschaAmount, uint256 foundationAmount) = _splitPayment(paymentAmount);

        _sendNative(_beneficiaries[0].wallet, kataschaAmount);
        _sendNative(_beneficiaries[1].wallet, foundationAmount);

        _recordPurchase(
            msg.sender,
            address(0),
            eonsAmount,
            paymentAmount,
            kataschaAmount,
            foundationAmount
        );
        emit BeneficiaryDistribution(kataschaAmount, foundationAmount, address(0));

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

    function withdrawNativeRefund() external nonReentrant {
        uint256 amount = nativeRefundCredit[msg.sender];
        require(amount > 0, "ETS-1: No refund credit");
        nativeRefundCredit[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETS-1: Refund withdrawal failed");
        emit NativeRefundWithdrawn(msg.sender, amount);
    }

    function _splitPayment(uint256 paymentAmount)
        internal
        view
        returns (uint256 kataschaAmount, uint256 foundationAmount)
    {
        kataschaAmount = (paymentAmount * _beneficiaries[0].percentage) / 100;
        foundationAmount = paymentAmount - kataschaAmount;
    }

    function _sendNative(address recipient, uint256 amount) internal {
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "ETS-1: Beneficiary native payment failed");
    }

    function _safeTokenTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IETS1ERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "ETS-1: Token transfer failed");
    }

    function _safeTokenTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IETS1ERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "ETS-1: Token transferFrom failed");
    }

    function _recordPurchase(
        address buyer,
        address paymentAsset,
        uint256 eonsAmount,
        uint256 paymentAmount,
        uint256 kataschaPayment,
        uint256 foundationPayment
    ) internal {
        uint256 purchaseId = _purchases.length;
        _purchases.push(
            PurchaseRecord(
                buyer,
                paymentAsset,
                eonsAmount,
                paymentAmount,
                kataschaPayment,
                foundationPayment,
                block.timestamp
            )
        );
        _purchasesByBuyer[buyer].push(purchaseId);
        emit EONSPurchased(
            buyer,
            paymentAsset,
            eonsAmount,
            paymentAmount,
            kataschaPayment,
            foundationPayment,
            purchaseId
        );
        _recordAssetTrace(address(0), buyer, eonsAmount, PURCHASE_ACTION, false);
    }

    function getPurchaseCount() external view returns (uint256) {
        return _purchases.length;
    }

    function getPurchase(uint256 index) external view returns (PurchaseRecord memory) {
        require(index < _purchases.length, "ETS-1: Invalid purchase index");
        return _purchases[index];
    }

    function getPurchasesPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (PurchaseRecord[] memory result)
    {
        require(offset <= _purchases.length, "ETS-1: Offset out of range");
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
        require(offset <= indexes.length, "ETS-1: Offset out of range");
        uint256 remaining = indexes.length - offset;
        uint256 count = limit < remaining ? limit : remaining;
        result = new PurchaseRecord[](count);
        for (uint256 i; i < count; i++) result[i] = _purchases[indexes[offset + i]];
    }

    // =============================================================
    // OWNER / PAUSE / BENEFICIARY FUNCTIONS
    // =============================================================

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ETS-1: Invalid new owner");
        require(newOwner != _owner, "ETS-1: Already the owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "ETS-1: Not pending owner");
        address previousOwner = _owner;
        _owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    function renounceOwnership() external onlyOwner {
        require(!paused && !circuitBreakerTripped, "ETS-1: Cannot renounce while paused");
        require(pendingOwner == address(0), "ETS-1: Pending ownership transfer exists");
        address previousOwner = _owner;
        _owner = address(0);
        emit OwnershipTransferred(previousOwner, address(0));
    }

    function pause() external onlyOwner {
        require(!paused, "ETS-1: Already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        require(paused, "ETS-1: Not paused");
        require(!circuitBreakerTripped, "ETS-1: Reset circuit breaker first");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setContentHash(bytes32 newHash) external onlyOwner {
        emit ContentHashUpdated(contentHash, newHash);
        contentHash = newHash;
    }

    function setContent(string calldata content) external onlyOwner returns (bytes32 newHash) {
        newHash = keccak256(bytes(content));
        emit ContentHashUpdated(contentHash, newHash);
        contentHash = newHash;
    }

    function setBeneficiaryWallet(uint256 index, address newWallet) external onlyOwner {
        require(index < 2, "ETS-1: Invalid beneficiary index");
        require(newWallet != address(0), "ETS-1: Invalid beneficiary wallet");
        address oldWallet = _beneficiaries[index].wallet;
        _beneficiaries[index].wallet = newWallet;
        emit BeneficiaryWalletUpdated(index, oldWallet, newWallet);
    }

    function getBeneficiaries() external view returns (Beneficiary[2] memory) {
        return _beneficiaries;
    }

    function getBeneficiary(uint256 index) external view returns (Beneficiary memory) {
        require(index < 2, "ETS-1: Invalid beneficiary index");
        return _beneficiaries[index];
    }
}
