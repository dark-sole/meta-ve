// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Interfaces.sol";

/**
 * @title VToken (V-AERO) V3
 * @notice Voting rights token for veAERO wrapper - 18 decimals
 */
contract VToken is ERC20, Ownable, ReentrancyGuard {
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error OnlySplitter();
    error SplitterAlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientUnlockedBalance();
    error TransferWhileLocked();
    error VotingNotStarted();
    error VotingEnded();
    error MustVoteWholeTokens();
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event SplitterSet(address indexed splitter);
    event Voted(address indexed user, address indexed pool, uint256 amount);
    event VotedPassive(address indexed user, uint256 amount);
    event LiquidationConfirmed(address indexed user, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Address of the VeAeroSplitter contract
    address public splitter;
    
    /// @notice Amount currently locked for epoch voting (per user)
    mapping(address => uint256) public lockedAmount;
    
    /// @notice Timestamp when lock expires (per user)
    mapping(address => uint256) public lockedUntil;

    /// @notice Total V-AERO locked for gauge voting this epoch
    uint256 public totalGaugeVotedThisEpoch;

    /// @dev Last epoch tracked for auto-reset
    uint256 private _lastGaugeEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor() ERC20("Voting AERO", "V-AERO") Ownable(msg.sender) {}
    
    // ═══════════════════════════════════════════════════════════════
    // ERC20 OVERRIDES - 18 DECIMALS (V3)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice V-AERO uses 18 decimals (standard ERC20)
     * @dev V3 change: Allows fractional transfers, voting requires whole tokens
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
        if (splitter != address(0)) revert SplitterAlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
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
     *      V3: Requires whole token amounts (amount % 1e18 == 0)
     * @param pool Pool address to vote for
     * @param amount V-AERO amount to vote (must be whole tokens, 18 decimals)
     */
    function vote(address pool, uint256 amount) external nonReentrant {
        if (pool == address(0)) revert ZeroAddress();
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
        
        // INTERACTIONS: Record vote in splitter (amount in whole tokens for bitpacking)
        uint256 wholeTokens = amount / 1e18;
        _splitter.recordGaugeVote(msg.sender, pool, wholeTokens);
        
        emit Voted(msg.sender, pool, amount);
    }
    
    /**
     * @notice Vote passively - follows the collective active vote proportions
     * @dev Passive votes are distributed proportionally to active gauge votes at execution.
     *      Useful for voters who want to participate but delegate allocation decisions.
     *      V3: Requires whole token amounts (amount % 1e18 == 0)
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
        
        // INTERACTIONS: Record passive vote in splitter (amount in whole tokens)
        uint256 wholeTokens = amount / 1e18;
        _splitter.recordPassiveVote(msg.sender, wholeTokens);
        
        emit VotedPassive(msg.sender, amount);
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
        
        // Transfer to splitter (permanent lock until liquidation resolves)
        _transfer(msg.sender, splitter, amount);
        
        // Record in splitter
        IVeAeroSplitter(splitter).recordVConfirmation(msg.sender, amount);
        
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
