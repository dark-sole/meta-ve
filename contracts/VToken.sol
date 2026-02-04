// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Interfaces.sol";
import "./DynamicGaugeVoteStorage.sol";
import "./DynamicPoolRegistry.sol";

/**
 * @title VToken (V-AERO) V.DELTA
 * @notice Voting rights token for veAERO wrapper - 18 decimals
 */
contract VToken is ERC20, Ownable, ReentrancyGuard {

    using DynamicGaugeVoteStorage for DynamicGaugeVoteStorage.PackedWeights;
    using DynamicPoolRegistry for DynamicPoolRegistry.Registry;
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error OnlySplitter();
    error AlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientUnlockedBalance();
    error TransferWhileLocked();
    error VotingNotStarted();
    error VotingEnded();
    error MustVoteWholeTokens();
    error StorageNotConfigured();
    error InvalidGauge();

    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event SplitterSet(address indexed splitter);
    event Voted(address indexed user, address indexed pool, uint256 amount);
    event VotedPassive(address indexed user, uint256 amount);
    event LiquidationConfirmed(address indexed user, uint256 amount);
    event LiquidationSet(address indexed liquidation);
    event VoteStorageConfigured(uint256 maxPools, uint256 bitsPerWeight);
    event EpochVotesReset(uint256 newEpoch);
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Address of the VeAeroSplitter contract
    address public splitter;
    address public liquidation;
    IVoter public immutable VOTER;
    
    /// @notice Amount currently locked for epoch voting (per user)
    mapping(address => uint256) public lockedAmount;
    
    /// @notice Timestamp when lock expires (per user)
    mapping(address => uint256) public lockedUntil;

    /// @notice Total V-AERO locked for gauge voting this epoch
    uint256 public totalGaugeVotedThisEpoch;

    /// @dev Last epoch tracked for auto-reset
    uint256 private _lastGaugeEpoch;

    // ═══════════════════════════════════════════════════════════════
    // VOTING STORAGE
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Vote storage configuration
    DynamicGaugeVoteStorage.Config public storageConfig;
    
    /// @notice Pool registry for vote tracking
    DynamicPoolRegistry.Registry internal poolRegistry;
    
    /// @notice Packed vote weights
    DynamicGaugeVoteStorage.PackedWeights internal currentWeights;
    
    /// @notice Current voting epoch
    uint256 public weightsEpoch;
    
    /// @notice Total passive votes this epoch (in whole tokens)
    // Passive votes (stored as whole tokens internally)
    uint256 internal _totalPassiveVotes;

    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor(address _voter) ERC20("Voting AERO", "V-AERO") Ownable(msg.sender) {
        if (_voter == address(0)) revert ZeroAddress();
        VOTER = IVoter(_voter);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ERC20 OVERRIDES - 18 DECIMALS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice V-AERO uses 18 decimals (standard ERC20)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Set splitter address (one-time)
     * @param _splitter Address of VeAeroSplitter contract
     */
    function setSplitter(address _splitter) external onlyOwner {
        if (_splitter == address(0)) revert ZeroAddress();
        if (splitter != address(0)) revert AlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }

    function setLiquidation(address _liquidation) external onlyOwner {
        if (_liquidation == address(0)) revert ZeroAddress();
        if (liquidation != address(0)) revert AlreadySet();
        liquidation = _liquidation;
        emit LiquidationSet(_liquidation);
    }

    /**
     * @notice Configure voting storage capacity
     * @dev Must be called by owner before first vote
     * @param maxPools Maximum number of pools to support
     * @param totalSupply Total V-AERO supply for weight calculation
     */
    function configureVotingStorage(uint256 maxPools, uint256 totalSupply) external onlyOwner {
        if (maxPools == 0) revert ZeroAmount();
        if (totalSupply == 0) revert ZeroAmount();
        
        
        
        // Configure storage
        storageConfig = DynamicGaugeVoteStorage.calculateConfig(
            totalSupply,  // First: total supply
            maxPools,     // Second: pool count
            0,            // Third: buffer
            DynamicGaugeVoteStorage.ABSOLUTE_MAX_SLOTS
        );
        // Initialize pool registry
        poolRegistry.initialize(maxPools);

        emit VoteStorageConfigured(maxPools, storageConfig.bitsPerPool);
    }
        
    // ═══════════════════════════════════════════════════════════════
    // SPLITTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    modifier onlySplitter() {
        if (msg.sender != splitter) revert OnlySplitter();
        _;
    }
    
    /**
     * @notice Mint V-AERO tokens (only callable by splitter)
     * @param to Recipient address
     * @param amount Amount to mint (18 decimals)
     */
    function mint(address to, uint256 amount) external onlySplitter {
        _mint(to, amount);
    }
    
    /**
     * @notice Burn V-AERO tokens (only callable by splitter)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlySplitter {
        _burn(from, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VOTING
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Vote on gauge allocation with V-AERO
     * @dev Locks voted tokens until epoch end. Single pool per call.
     * Requires whole token amounts (amount % 1e18 == 0)
     * @param pool Pool address to vote for
     * @param amount V-AERO amount to vote (must be whole tokens, 18 decimals)
     */
    function vote(address pool, uint256 amount) external nonReentrant {
        if (pool == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount % 1e18 != 0) revert MustVoteWholeTokens();
        
        // Get splitter reference
        IVeAeroSplitter _splitter = IVeAeroSplitter(splitter);
        
        // Validate gauge exists and is alive
        address gauge = VOTER.gauges(pool);
        if (gauge == address(0)) revert InvalidGauge();
        if (!VOTER.isAlive(gauge)) revert InvalidGauge();
        
        // Voting window check
        uint256 votingStart = _splitter.votingStartTime();
        uint256 votingEnd = _splitter.votingEndTime();
        if (block.timestamp < votingStart) revert VotingNotStarted();
        if (block.timestamp > votingEnd) revert VotingEnded();
        
        // Check unlocked balance
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();

        // Auto-reset tracking on new epoch
        uint256 currentEpoch = _splitter.currentEpoch();
        if (currentEpoch != _lastGaugeEpoch) {
            totalGaugeVotedThisEpoch = 0;
            _lastGaugeEpoch = currentEpoch;
        }
        totalGaugeVotedThisEpoch += amount;
        
        // EFFECTS: Lock tokens until epoch end
        uint256 epochEnd = _splitter.epochEndTime();

        // Reset locked amount if previous lock has expired
        if (block.timestamp >= lockedUntil[msg.sender]) {
            lockedAmount[msg.sender] = amount;
        } else {
            lockedAmount[msg.sender] += amount;
        }
        lockedUntil[msg.sender] = epochEnd;
        
        // STORE VOTE INTERNALLY
        uint256 wholeTokens = amount / 1e18;
        (uint256 poolIndex, ) = poolRegistry.getOrRegister(pool);
        currentWeights.addWeight(storageConfig, poolIndex, wholeTokens);
        
        emit Voted(msg.sender, pool, amount);
    }
    
    /**
     * @notice Vote passively - follows the collective active vote proportions
     * @dev Passive votes are distributed proportionally to active gauge votes at execution.
     *      Useful for voters who want to participate but delegate allocation decisions.
     *      Requires whole token amounts (amount % 1e18 == 0)
     * @param amount V-AERO amount to vote passively (must be whole tokens, 18 decimals)
     */
    function votePassive(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (amount % 1e18 != 0) revert MustVoteWholeTokens();
        
        // Get splitter reference
        IVeAeroSplitter _splitter = IVeAeroSplitter(splitter);
        
        // Voting window check
        uint256 votingStart = _splitter.votingStartTime();
        uint256 votingEnd = _splitter.votingEndTime();
        if (block.timestamp < votingStart) revert VotingNotStarted();
        if (block.timestamp > votingEnd) revert VotingEnded();
        
        // Check unlocked balance
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();

        // Auto-reset tracking on new epoch
        uint256 currentEpoch = _splitter.currentEpoch();
        if (currentEpoch != _lastGaugeEpoch) {
            totalGaugeVotedThisEpoch = 0;
            _lastGaugeEpoch = currentEpoch;
        }
        totalGaugeVotedThisEpoch += amount;
        
        // EFFECTS: Lock tokens until epoch end
        uint256 epochEnd = _splitter.epochEndTime();

        // Reset locked amount if previous lock has expired
        if (block.timestamp >= lockedUntil[msg.sender]) {
            lockedAmount[msg.sender] = amount;
        } else {
            lockedAmount[msg.sender] += amount;
        }
        lockedUntil[msg.sender] = epochEnd;
        
        // STORE PASSIVE VOTE INTERNALLY (no longer calls splitter.recordPassiveVote)
        uint256 wholeTokens = amount / 1e18;
        _totalPassiveVotes += wholeTokens;
        
        emit VotedPassive(msg.sender, amount);
    }
    // ═══════════════════════════════════════════════════════════════
    // VOTE AGGREGATION (For Splitter)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get aggregated votes for splitter execution
     * @dev Called by splitter during executeGaugeVote()
     * @return pools Array of pool addresses with votes
     * @return weights Array of vote weights (sorted descending)
     */
    function getAggregatedVotes() external view returns (
        address[] memory pools,
        uint256[] memory weights
    ) {
        // 1. Get all pools with votes
        uint256 maxPools = storageConfig.maxPools;
        address[] memory allPools = new address[](maxPools);
        uint256[] memory allWeights = new uint256[](maxPools);
        uint256 count = 0;
        
        // Iterate through pool registry
        for (uint256 i = 0; i < poolRegistry.count(); i++) {
            address pool = poolRegistry.getPool(i);
            if (pool == address(0)) continue;
            
            uint256 weight = currentWeights.getWeight(storageConfig, i);
            if (weight == 0) continue;
            
            allPools[count] = pool;
            allWeights[count] = weight;
            count++;
        }
        
        // 2. Distribute passive votes proportionally
        if (_totalPassiveVotes > 0 && count > 0) {
            uint256 totalActive = 0;
            for (uint256 i = 0; i < count; i++) {
                totalActive += allWeights[i];
            }
            
            if (totalActive > 0) {
                for (uint256 i = 0; i < count; i++) {
                    uint256 passiveShare = (allWeights[i] * _totalPassiveVotes) / totalActive;
                    allWeights[i] += passiveShare;
                }
            }
        }
        
        // 3. Sort by weight (descending)
        if (count > 0) {
            _quickSort(allPools, allWeights, 0, int256(count) - 1);
        }
        
        // 4. Trim to actual count
        pools = new address[](count);
        weights = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            pools[i] = allPools[i];
            weights[i] = allWeights[i];
        }
        
        return (pools, weights);
    }
    
    /**
     * @notice Reset votes for new epoch
     * @dev Only callable by splitter after execution
     */
    function resetVotesForNewEpoch() external {
        if (msg.sender != splitter) revert OnlySplitter();
        
        currentWeights.clearAll();
        poolRegistry.clear();
        _totalPassiveVotes = 0;
        totalGaugeVotedThisEpoch = 0;  // Reset total for new epoch
        _lastGaugeEpoch = 0;
        weightsEpoch++;
        
        emit EpochVotesReset(weightsEpoch);
    }
    
    /**
     * @notice Sort pools by weight (descending)
     * @dev QuickSort implementation
     */
    function _quickSort(
        address[] memory pools,
        uint256[] memory weights,
        int256 left,
        int256 right
    ) internal pure {
        if (left >= right) return;
        
        int256 i = left;
        int256 j = right;
        uint256 pivot = weights[uint256(left + (right - left) / 2)];
        
        while (i <= j) {
            while (weights[uint256(i)] > pivot) i++;
            while (pivot > weights[uint256(j)]) j--;
            
            if (i <= j) {
                // Swap pools
                (pools[uint256(i)], pools[uint256(j)]) = (pools[uint256(j)], pools[uint256(i)]);
                // Swap weights
                (weights[uint256(i)], weights[uint256(j)]) = (weights[uint256(j)], weights[uint256(i)]);
                i++;
                j--;
            }
        }
        
        if (left < j) _quickSort(pools, weights, left, j);
        if (i < right) _quickSort(pools, weights, i, right);
    }

    
    /**
     * @notice Confirm liquidation with V-AERO (VConfirm phase)
     * @dev Transfers tokens to splitter - permanent commitment until liquidation resolves
     * @param amount V-AERO amount to lock for liquidation confirmation
     */
    function confirmLiquidation(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();
        
        // Transfer to liquidation contract (not splitter)
        _transfer(msg.sender, liquidation, amount);
        
        // Record in liquidation contract
        IVeAeroLiquidation(liquidation).recordVConfirmation(msg.sender, amount);
        
        emit LiquidationConfirmed(msg.sender, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // BALANCE HELPERS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get unlocked (transferable/votable) balance
     * @param account Address to check
     * @return Unlocked balance
     */
    function unlockedBalanceOf(address account) public view returns (uint256) {
        uint256 total = balanceOf(account);
        
        // If lock expired, all tokens are unlocked
        if (block.timestamp >= lockedUntil[account]) {
            return total;
        }
        
        // Otherwise subtract locked amount
        uint256 locked = lockedAmount[account];
        return total > locked ? total - locked : 0;
    }
    
    /**
     * @notice Check if account has any locked tokens
     * @param account Address to check
     * @return True if tokens are locked
     */
    function isLocked(address account) external view returns (bool) {
        return block.timestamp < lockedUntil[account] && lockedAmount[account] > 0;
    }
    
    /**
     * @notice Get total number of pools with votes
     */
    function getTotalVotedPools() external view returns (uint256) {
        return poolRegistry.count();
    }
    
    /**
     * @notice Get votes for a specific pool
     * @param pool Pool address
     * @return Vote weight in wei
     */
    function getPoolVotes(address pool) external view returns (uint256) {
        if (!poolRegistry.isRegistered(pool)) return 0;
        uint256 index = poolRegistry.getIndex(pool);
        return currentWeights.getWeight(storageConfig, index) * 1e18;
    }
    
    /**
     * @notice Get total passive votes for this epoch
     * @return Total passive votes in whole tokens
     */
    function totalPassiveVotes() external view returns (uint256) {
        return _totalPassiveVotes * 1e18;  // Already stored as whole tokens
    }
    /**
    * @notice Get user's currently locked amount (0 if lock expired)
    * @param user Address to check
    * @return Locked amount, or 0 if lock has expired
    */
    function currentLockedAmount(address user) external view returns (uint256) {
        if (block.timestamp >= lockedUntil[user]) return 0;
        return lockedAmount[user];
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TRANSFER RESTRICTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @dev Override transfer to enforce lock
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Minting and burning always allowed
        if (from != address(0) && to != address(0)) {
            // For transfers, check unlocked balance
            if (amount > unlockedBalanceOf(from)) {
                revert TransferWhileLocked();
            }
        }
        
        super._update(from, to, amount);
    }
}
