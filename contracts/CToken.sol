// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Interfaces.sol";

/**
 * @title CToken (C-AERO) V4
 * @notice Capital rights token with integrated META distribution
 * @dev Gas optimized, CEI compliant
 * 
 * REWARDS:
 * - AERO fees: Distributed by VeAeroSplitter (50% of trading fees)
 * - META rewards: CToken pulls S/2 of incentives from Meta via claimForVEPool()
 */
contract CToken is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ════════════════════════════════════════════════════════════════════════
    
    uint256 public constant PRECISION = 1e18;
    
    // ════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ════════════════════════════════════════════════════════════════════════
    
    error OnlySplitter();
    error SplitterAlreadySet();
    error MetaAlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientUnlockedBalance();
    error TransferWhileLocked();
    error VotingNotStarted();
    error VotingEnded();
    error InvalidChoice();
    error MustVoteWholeTokens();
    error NothingToClaim();
    error MetaNotSet();
    
    // ════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ════════════════════════════════════════════════════════════════════════
    
    event SplitterSet(address indexed splitter);
    event MetaSet(address indexed meta);
    event EmissionsVoted(address indexed user, int8 choice, uint256 amount);
    event LiquidationVoted(address indexed user, uint256 amount);
    event MetaDistributed(uint256 amount, uint256 newMetaPerCToken);
    event MetaClaimed(address indexed user, uint256 amount);
    
    // ════════════════════════════════════════════════════════════════════════
    // STATE
    // ════════════════════════════════════════════════════════════════════════
    
    address public splitter;
    IMeta public meta;
    
    /// @notice META per C-AERO token (scaled by PRECISION)
    uint256 public metaPerCToken;
    
    /// @notice User META debt for distribution tracking
    mapping(address => uint256) public userMetaDebt;
    
    /// @notice User claimable META
    mapping(address => uint256) public userClaimableMeta;
    
    /// @notice Amount locked for voting (per user)
    mapping(address => uint256) public lockedAmount;
    
    /// @notice Lock expiry timestamp (per user)
    mapping(address => uint256) public lockedUntil;
    
    /// @notice Total C-AERO locked for emissions voting this epoch
    uint256 public totalEmissionsVotedThisEpoch;
    
    /// @dev Last epoch for auto-reset
    uint256 private _lastEmissionsEpoch;
    
    // ════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ════════════════════════════════════════════════════════════════════════
    
    constructor() ERC20("Capital AERO", "C-AERO") Ownable(msg.sender) {}
    
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // SETUP (Owner)
    // ════════════════════════════════════════════════════════════════════════
    
    function setSplitter(address _splitter) external onlyOwner {
        if (_splitter == address(0)) revert ZeroAddress();
        if (splitter != address(0)) revert SplitterAlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }
    
    function setMeta(address _meta) external onlyOwner {
        if (_meta == address(0)) revert ZeroAddress();
        if (address(meta) != address(0)) revert MetaAlreadySet();
        meta = IMeta(_meta);
        emit MetaSet(_meta);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // SPLITTER FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════
    
    modifier onlySplitter() {
        if (msg.sender != splitter) revert OnlySplitter();
        _;
    }
    
    function mint(address to, uint256 amount) external onlySplitter {
        _checkpointUser(to);
        _mint(to, amount);
        _updateUserDebt(to);
    }
    
    function burn(address from, uint256 amount) external onlySplitter {
        _checkpointUser(from);
        _burn(from, amount);
        _updateUserDebt(from);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // META DISTRIBUTION (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Pull META from Meta contract and update distribution index
     * @dev Anyone can call. CToken is whitelisted VE pool in Meta.
     */
    function collectMeta() external nonReentrant returns (uint256 metaClaimed) {
        IMeta _meta = meta;  // Cache
        if (address(_meta) == address(0)) revert MetaNotSet();
        
        // Update Meta index if stale
        if (_meta.needsIndexUpdate()) {
            _meta.updateIndex();
        }
        
        // INTERACTIONS - Pull META (Meta handles CEI internally)
        metaClaimed = _meta.claimForVEPool();
        
        // EFFECTS - Update index after receiving
        if (metaClaimed > 0) {
            uint256 totalC = totalSupply();
            if (totalC > 0) {
                metaPerCToken += (metaClaimed * PRECISION) / totalC;
                emit MetaDistributed(metaClaimed, metaPerCToken);
            }
        }
    }
    
    /**
     * @notice Claim pending META rewards
     */
    function claimMeta() external nonReentrant returns (uint256 amount) {
        IMeta _meta = meta;
        if (address(_meta) == address(0)) revert MetaNotSet();
        
        // Try to collect any new META first (silent fail OK)
        _tryCollectMeta(_meta);
        
        // Checkpoint user
        _checkpointUser(msg.sender);
        
        amount = userClaimableMeta[msg.sender];
        if (amount == 0) revert NothingToClaim();
        
        // EFFECTS
        userClaimableMeta[msg.sender] = 0;
        
        // INTERACTIONS
        IERC20(address(_meta)).safeTransfer(msg.sender, amount);
        
        emit MetaClaimed(msg.sender, amount);
    }
    
    /**
     * @notice Get pending META rewards for a user
     */
    function pendingMeta(address user) external view returns (uint256) {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * metaPerCToken) / PRECISION;
        uint256 pending = userClaimableMeta[user] + userShare - userMetaDebt[user];
        
        // Add estimated pending from Meta contract
        IMeta _meta = meta;
        if (address(_meta) != address(0)) {
            (, , uint256 poolPending, ) = _meta.getPoolInfo(address(this));
            if (poolPending > 0) {
                uint256 totalC = totalSupply();
                if (totalC > 0) {
                    pending += (poolPending * userBal) / totalC;
                }
            }
        }
        
        return pending;
    }
    
    function _tryCollectMeta(IMeta _meta) internal {
        try _meta.needsIndexUpdate() returns (bool needsUpdate) {
            if (needsUpdate) {
                try _meta.updateIndex() {} catch {}
            }
        } catch {}
        
        try _meta.claimForVEPool() returns (uint256 claimed) {
            if (claimed > 0) {
                uint256 totalC = totalSupply();
                if (totalC > 0) {
                    metaPerCToken += (claimed * PRECISION) / totalC;
                    emit MetaDistributed(claimed, metaPerCToken);
                }
            }
        } catch {}
    }
    
    function _checkpointUser(address user) internal {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * metaPerCToken) / PRECISION;
        uint256 debt = userMetaDebt[user];
        if (userShare > debt) {
            userClaimableMeta[user] += userShare - debt;
        }
    }
    
    function _updateUserDebt(address user) internal {
        userMetaDebt[user] = (balanceOf(user) * metaPerCToken) / PRECISION;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // VOTING
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Vote on AERO emissions
     * @param choice -1 (decrease), 0 (hold), +1 (increase)
     * @param amount C-AERO amount (must be whole tokens)
     */
    function voteEmissions(int8 choice, uint256 amount) external nonReentrant {
        // CHECKS
        if (choice < -1 || choice > 1) revert InvalidChoice();
        if (amount == 0) revert ZeroAmount();
        if (amount % 1e18 != 0) revert MustVoteWholeTokens();
        
        IVeAeroSplitter _splitter = IVeAeroSplitter(splitter);
        
        uint256 votingStart = _splitter.votingStartTime();
        uint256 votingEnd = _splitter.votingEndTime();
        if (block.timestamp < votingStart) revert VotingNotStarted();
        if (block.timestamp > votingEnd) revert VotingEnded();
        
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();
        
        // Auto-reset on new epoch
        uint256 currentEpoch = _splitter.currentEpoch();
        if (currentEpoch != _lastEmissionsEpoch) {
            totalEmissionsVotedThisEpoch = 0;
            _lastEmissionsEpoch = currentEpoch;
        }
        
        // EFFECTS
        totalEmissionsVotedThisEpoch += amount;
        
        uint256 epochEnd = _splitter.epochEndTime();
        if (block.timestamp >= lockedUntil[msg.sender]) {
            lockedAmount[msg.sender] = amount;
        } else {
            lockedAmount[msg.sender] += amount;
        }
        lockedUntil[msg.sender] = epochEnd;
        
        // INTERACTIONS
        _splitter.recordEmissionsVote(msg.sender, choice, amount / 1e18);
        
        emit EmissionsVoted(msg.sender, choice, amount);
    }
    
    /**
     * @notice Vote for liquidation (transfers tokens to splitter)
     */
    function voteLiquidation(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();
        
        // EFFECTS - Checkpoint META before transfer
        _checkpointUser(msg.sender);
        
        // Transfer includes _update which handles debt
        _transfer(msg.sender, splitter, amount);
        
        // INTERACTIONS
        IVeAeroSplitter(splitter).recordCLock(msg.sender, amount);
        
        emit LiquidationVoted(msg.sender, amount);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // BALANCE HELPERS
    // ════════════════════════════════════════════════════════════════════════
    
    function unlockedBalanceOf(address account) public view returns (uint256) {
        uint256 total = balanceOf(account);
        if (block.timestamp >= lockedUntil[account]) {
            return total;
        }
        uint256 locked = lockedAmount[account];
        return total > locked ? total - locked : 0;
    }
    
    function isLocked(address account) external view returns (bool) {
        return block.timestamp < lockedUntil[account] && lockedAmount[account] > 0;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // TRANSFER HOOK (CEI via splitter.onCTokenTransfer)
    // ════════════════════════════════════════════════════════════════════════
    
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Regular transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            // CHECKS
            if (amount > unlockedBalanceOf(from)) {
                revert TransferWhileLocked();
            }
            
            // EFFECTS - Checkpoint META for both parties
            _checkpointUser(from);
            _checkpointUser(to);
            
            // INTERACTIONS - Splitter handles AERO fee checkpoints
            // (settles sender's unclaimed, weight-average for receiver)
            address _splitter = splitter;
            if (_splitter != address(0)) {
                IVeAeroSplitter(_splitter).onCTokenTransfer(from, to, amount);
            }
        }
        
        super._update(from, to, amount);
        
        // Update META debts after balance change
        if (from != address(0)) {
            _updateUserDebt(from);
        }
        if (to != address(0)) {
            _updateUserDebt(to);
        }
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════
    
    function isMetaActive() external view returns (bool) {
        return address(meta) != address(0);
    }
    
    function getMetaAccumulator() external view returns (uint256) {
        return metaPerCToken;
    }
}
