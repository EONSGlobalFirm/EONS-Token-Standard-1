// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract EONS-TOKEN-STANDARD-1/ETS-1 {
}
/**
 * @title ETS-1 — Fungible Token Standard With Customizable Actions
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

contract ETS1 {

    // =============================================================
    // TOKEN DATA
    // =============================================================
    string public constant name = "EONS";
    string public constant symbol = "E";
    uint8 public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18;
    bytes32 public contentHash;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

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

    // =============================================================
    // BENEFICIARIES
    // =============================================================

    struct Beneficiary {
        string name;
        uint256 percentage;
        address wallet;
    }

    Beneficiary[2] private _beneficiaries;

    // =============================================================
    // CONTRACT STATE / EVENTS
    // =============================================================

    bool public paused;

    event Transfer(address indexed from, address indexed to, uint256 value);
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

    // When enabled by a holder, that wallet cannot send tokens until disabled.
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

    // Values are denominated in the token's smallest units (18 decimals).
    uint256 public circuitBreakerThreshold; // 0 = disabled
    uint256 public circuitBreakerWindow;    // seconds; 0 = rate limit disabled
    uint256 public circuitBreakerLimit;     // amount per sender per window; 0 = disabled
    bool public circuitBreakerTripped;

    mapping(address => uint256) private _cbWindowStart;
    mapping(address => uint256) private _cbWindowSpent;

    event CircuitBreakerTriggered(address indexed from, address indexed to, uint256 amount);
    event CircuitBreakerThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event CircuitBreakerLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event CircuitBreakerWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event CircuitBreakerReset();

    function setCircuitBreaker(
        uint256 threshold,
        uint256 window,
        uint256 limit
    ) external onlyOwner {
        emit CircuitBreakerThresholdUpdated(circuitBreakerThreshold, threshold);
        emit CircuitBreakerWindowUpdated(circuitBreakerWindow, window);
        emit CircuitBreakerLimitUpdated(circuitBreakerLimit, limit);

        circuitBreakerThreshold = threshold;
        circuitBreakerWindow = window;
        circuitBreakerLimit = limit;
    }

    function resetCircuitBreaker() external onlyOwner {
        require(circuitBreakerTripped, "ETS-1: Circuit breaker not tripped");
        circuitBreakerTripped = false;
        emit CircuitBreakerReset();
    }

    /**
     * @dev Returns false and persistently pauses the contract when a global
     *      circuit-breaker rule is hit. It deliberately does not revert:
     *      reverting would also undo the pause state change.
     */
    function _enforceCircuitBreaker(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
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

    struct AssetTrace {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        bytes32 actionId;
    }

    AssetTrace[] private _assetTraces;
    mapping(address => uint256[]) private _tracesByAddress;
    mapping(bytes32 => uint256[]) private _tracesByAction;

    event AssetTraced(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 indexed actionId,
        uint256 timestamp
    );

    function _recordAssetTrace(
        address from,
        address to,
        uint256 amount,
        bytes32 actionId
    ) internal {
        uint256 traceIndex = _assetTraces.length;
        uint256 timestamp = block.timestamp;

        _assetTraces.push(AssetTrace(from, to, amount, timestamp, actionId));
        _tracesByAddress[from].push(traceIndex);
        if (to != from) {
            _tracesByAddress[to].push(traceIndex);
        }
        _tracesByAction[actionId].push(traceIndex);

        emit AssetTraced(from, to, amount, actionId, timestamp);
    }

    function logAssetTrace(
        address from,
        address to,
        uint256 amount,
        bytes32 actionId
    ) external onlyOwner {
        require(from != address(0), "ETS-1: Invalid trace sender");
        require(to != address(0), "ETS-1: Invalid trace receiver");
        require(_actions[actionId], "ETS-1: Action not registered");
        _recordAssetTrace(from, to, amount, actionId);
    }

    function getAssetTraceCount() external view returns (uint256) {
        return _assetTraces.length;
    }

    function getAssetTrace(uint256 index) external view returns (AssetTrace memory) {
        require(index < _assetTraces.length, "ETS-1: Invalid trace index");
        return _assetTraces[index];
    }

    function getAssetTracesForAddress(address account)
        external
        view
        returns (AssetTrace[] memory result)
    {
        uint256[] storage indexes = _tracesByAddress[account];
        result = new AssetTrace[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            result[i] = _assetTraces[indexes[i]];
        }
    }

    function getAssetTracesByAction(bytes32 actionId)
        external
        view
        returns (AssetTrace[] memory result)
    {
        uint256[] storage indexes = _tracesByAction[actionId];
        result = new AssetTrace[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            result[i] = _assetTraces[indexes[i]];
        }
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
        for (uint256 i = 0; i < count; i++) {
            result[i] = _assetTraces[offset + i];
        }
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

        for (uint256 i = 0; i < count; i++) {
            AssetTrace storage trace = _assetTraces[indexes[i]];
            from[i] = trace.from;
            to[i] = trace.to;
            amounts[i] = trace.amount;
            timestamps[i] = trace.timestamp;
            actionIds[i] = trace.actionId;
        }
    }

    function getTracedVolumeForAddress(address account)
        external
        view
        returns (uint256 sent, uint256 received)
    {
        uint256[] storage indexes = _tracesByAddress[account];
        for (uint256 i = 0; i < indexes.length; i++) {
            AssetTrace storage trace = _assetTraces[indexes[i]];
            if (trace.from == account) sent += trace.amount;
            if (trace.to == account) received += trace.amount;
        }
    }

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    constructor(address kataschaWallet) {
        // The account that submits the deployment transaction becomes owner.
        address initialOwner = msg.sender;

        require(initialOwner != address(0), "ETS-1: Invalid owner");
        require(kataschaWallet != address(0), "ETS-1: Invalid beneficiary wallet");

        _owner = initialOwner;
        _balances[initialOwner] = TOTAL_SUPPLY;

        _beneficiaries[0] = Beneficiary("Katascha White", 50, kataschaWallet);
        _beneficiaries[1] = Beneficiary("Eons Global Foundation", 50, kataschaWallet);

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

    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    function transfer(address to, uint256 amount) external notPaused returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external notPaused returns (bool) {
        require(spender != address(0), "ETS-1: Invalid spender");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        notPaused
        returns (bool)
    {
        require(spender != address(0), "ETS-1: Invalid spender");
        uint256 newAllowance = _allowances[msg.sender][spender] + addedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        notPaused
        returns (bool)
    {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ETS-1: Allowance below zero");
        uint256 newAllowance = currentAllowance - subtractedValue;
        _allowances[msg.sender][spender] = newAllowance;
        emit Approval(msg.sender, spender, newAllowance);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        notPaused
        returns (bool)
    {
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

        // A triggered global breaker records the pause and rejects this transfer
        // by returning false rather than reverting the pause state.
        if (!_enforceCircuitBreaker(from, to, amount)) return false;

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        _recordAssetTrace(from, to, amount, TRANSFER_ACTION);
        return true;
    }

    // =============================================================
    // OWNER / PAUSE / BENEFICIARY FUNCTIONS
    // =============================================================

    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Starts an ownership change. The proposed new owner must call
     *         acceptOwnership() from that address to complete the switch.
     * @dev The current owner remains owner until the pending owner accepts.
     *      Calling this again replaces the pending owner and cancels the
     *      previous proposal.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ETS-1: Invalid new owner");
        require(newOwner != _owner, "ETS-1: Already the owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /** @notice Completes the ownership switch; only the proposed owner can call. */
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "ETS-1: Not pending owner");
        address previousOwner = _owner;
        _owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    /** @notice Permanently removes owner privileges. This action cannot be undone. */
    function renounceOwnership() external onlyOwner {
        address previousOwner = _owner;
        _owner = address(0);
        pendingOwner = address(0);
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

    function getBeneficiaries() external view returns (Beneficiary[2] memory) {
        return _beneficiaries;
    }

    function getBeneficiary(uint256 index) external view returns (Beneficiary memory) {
        require(index < 2, "ETS-1: Invalid beneficiary index");
        return _beneficiaries[index];
    }
}

