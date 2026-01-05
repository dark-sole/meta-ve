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
 * @title CToken (C-AERO) V.GAMMA
 * @notice Capital rights token with integrated META distribution
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
    error AlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientUnlockedBalance();
    error TransferWhileLocked();
    error VotingNotStarted();
    error VotingEnded();
    error InvalidChoice();
    error MustVoteWholeTokens();
    error NothingToClaim();
    error NotSet();
    
    // ════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ════════════════════════════════════════════════════════════════════════
    
    event SplitterSet(address indexed splitter);
    event MetaSet(address indexed meta);
    event EmissionsVoted(address indexed user, int8 choice, uint256 amount);
    event LiquidationVoted(address indexed user, uint256 amount);
    event MetaDistributed(uint256 amount, uint256 newMetaPerCToken);
    event MetaClaimed(address indexed user, uint256 amount);
    event LiquidationSet(address indexed liquidation);
    event AeroSet(address indexed aero);
    event EmissionsVoteLibSet(address indexed lib);
    event FeesCollected(uint256 amount, uint256 newFeePerCToken);
    event FeesClaimed(address indexed user, uint256 amount);
    
    // ════════════════════════════════════════════════════════════════════════
    // STATE
    // ════════════════════════════════════════════════════════════════════════

    address public splitter;
    IMeta public meta;
    address public liquidation;
    IEmissionsVoteLib public emissionsVoteLib;
    
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
        if (splitter != address(0)) revert AlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }
    
    function setMeta(address _meta) external onlyOwner {
        if (_meta == address(0)) revert ZeroAddress();
        if (address(meta) != address(0)) revert AlreadySet();
        meta = IMeta(_meta);
        emit MetaSet(_meta);
    }
    
    function setLiquidation(address _liquidation) external onlyOwner {
        if (_liquidation == address(0)) revert ZeroAddress();
        if (liquidation != address(0)) revert AlreadySet();
        liquidation = _liquidation;
        emit LiquidationSet(_liquidation);
    }
    /**
    * @notice Set AERO token address (one-time)
    * @param _aero Address of AERO token
    */
    function setAero(address _aero) external onlyOwner {
        if (_aero == address(0)) revert ZeroAddress();
        if (address(aero) != address(0)) revert AlreadySet();
        aero = IERC20(_aero);
        emit AeroSet(_aero);
    }
    /**
     * @notice Set EmissionsVoteLib address (one-time)
     * @param _lib EmissionsVoteLib contract address
     */
    function setEmissionsVoteLib(address _lib) external onlyOwner {
        if (_lib == address(0)) revert ZeroAddress();
        if (address(emissionsVoteLib) != address(0)) revert AlreadySet();
        emissionsVoteLib = IEmissionsVoteLib(_lib);
        emit EmissionsVoteLibSet(_lib);
    }

    
    // ════════════════════════════════════════════════════════════════════════
    // SPLITTER FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════
    
    modifier onlySplitter() {
        if (msg.sender != splitter) revert OnlySplitter();
        _;
    }
    
    function mint(address to, uint256 amount) external onlySplitter {
        _collectPendingFees(); 
        _collectPendingMeta();
        _checkpointUser(to);
        _checkpointUserFee(to);  
        _mint(to, amount);
        _updateUserDebt(to);
        _updateUserFeeDebt(to);  
    }
    
    function burn(address from, uint256 amount) external onlySplitter {
        _checkpointUser(from);
        _checkpointUserFee(from);  
        _burn(from, amount);
        _updateUserDebt(from);
        _updateUserFeeDebt(from);  
    }

    // ═══════════════════════════════════════════════════════════════
    // AERO FEE DISTRIBUTION STATE
    // ═══════════════════════════════════════════════════════════════

    /// @notice AERO token for fee distribution
    IERC20 public aero;

    /// @notice Accumulated AERO fees per C-token (scaled by PRECISION)
    uint256 public feePerCToken;

    /// @notice User's fee debt for distribution calculation
    mapping(address => uint256) public userFeeDebt;

    /// @notice User's claimable AERO fees
    mapping(address => uint256) public userClaimableFee;
    
    // ════════════════════════════════════════════════════════════════════════
    // META DISTRIBUTION
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Pull META from Meta contract and update distribution index
     * @dev Anyone can call. CToken is whitelisted VE pool in Meta.
     */
    function collectMeta() external nonReentrant returns (uint256 metaClaimed) {
        IMeta _meta = meta;  // Cache
        if (address(_meta) == address(0)) revert NotSet();
        
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
    * @notice Collect AERO fees from Meta contract
    * @dev Anyone can call - updates fee index for all holders
    * @return feeClaimed Amount of AERO collected
    */
    function collectFees() external nonReentrant returns (uint256 feeClaimed) {
        IMeta _meta = meta;
        if (address(_meta) == address(0)) revert NotSet();
        
        // Pull AERO fees from Meta (CToken must be whitelisted VE pool)
        feeClaimed = _meta.claimFeesForVEPool();
        
        if (feeClaimed > 0) {
            uint256 totalC = totalSupply();
            if (totalC > 0) {
                feePerCToken += (feeClaimed * PRECISION) / totalC;
                emit FeesCollected(feeClaimed, feePerCToken);
            }
        }
    }

    // collect pending fees to avoid depositor attack
    function _collectPendingFees() internal {
        IMeta _meta = meta;
        if (address(_meta) == address(0)) return; // Skip if not set
        
        uint256 feeClaimed = _meta.claimFeesForVEPool();
        
        if (feeClaimed > 0) {
            uint256 totalC = totalSupply();
            if (totalC > 0) {
                feePerCToken += (feeClaimed * PRECISION) / totalC;
                emit FeesCollected(feeClaimed, feePerCToken);
            }
        }
    }

    function _collectPendingMeta() internal {
        IMeta _meta = meta;
        if (address(_meta) == address(0)) return;
        
        uint256 metaClaimed = _meta.claimForVEPool();
        
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
        if (address(_meta) == address(0)) revert NotSet();
        
        // ═══════════════════════════════════════════════════════════════════
        // EFFECTS FIRST - Update all state before any external calls
        // ═══════════════════════════════════════════════════════════════════
        
        // Checkpoint user rewards
        _checkpointUser(msg.sender);
        
        _updateUserDebt(msg.sender);
        
        // Get claimable amount
        amount = userClaimableMeta[msg.sender];
        if (amount == 0) revert NothingToClaim();
        
        // Clear claimable
        userClaimableMeta[msg.sender] = 0;
        
        // ═══════════════════════════════════════════════════════════════════
        // INTERACTIONS LAST - All external calls after state is finalized
        // ═══════════════════════════════════════════════════════════════════
        
        // Try to collect any new META (optional, can fail silently)
        _tryCollectMeta(_meta);
        
        // Transfer META to user
        IERC20(address(_meta)).safeTransfer(msg.sender, amount);
        
        emit MetaClaimed(msg.sender, amount);
    }
    /**
    * @notice Claim accumulated AERO fees
    * @return amount Amount of AERO claimed
    */
    function claimFees() external nonReentrant returns (uint256 amount) {
        if (address(aero) == address(0)) revert NotSet();
        
        // Checkpoint user's fee accrual
        _checkpointUserFee(msg.sender);
        _updateUserFeeDebt(msg.sender);
        
        amount = userClaimableFee[msg.sender];
        if (amount == 0) revert NothingToClaim();
        
        userClaimableFee[msg.sender] = 0;
        aero.safeTransfer(msg.sender, amount);
        
        emit FeesClaimed(msg.sender, amount);
    }
        
    /**
     * @notice Get pending META rewards for a user
     */
    function pendingMeta(address user) external view returns (uint256) {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * metaPerCToken) / PRECISION;
        uint256 debt = userMetaDebt[user];
        uint256 pending = userClaimableMeta[user];
        
        // Add unclaimed share
        if (userShare > debt) {
            pending += userShare - debt;
        }
        
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
    /**
    * @notice Get pending AERO fees for a user
    * @param user Address to check
    * @return Pending AERO amount
    */
    function pendingFees(address user) external view returns (uint256) {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * feePerCToken) / PRECISION;
        uint256 debt = userFeeDebt[user];
        uint256 pending = userClaimableFee[user];
        
        if (userShare > debt) {
            pending += userShare - debt;
        }
        
        // Also check uncollected fees in Meta
        IMeta _meta = meta;
        if (address(_meta) != address(0)) {
            uint256 poolPending = _meta.poolFeeAccrued(address(this));
            if (poolPending > 0) {
                uint256 totalC = totalSupply();
                if (totalC > 0) {
                    pending += (poolPending * userBal) / totalC;
                }
            }
        }
        
        return pending;
    }
    
    /**
     * @dev Try to collect META - silent fail OK
     * @notice V10: This is now called AFTER state updates in claimMeta
     */
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
    
    /**
     * @dev Checkpoint user - accumulate pending rewards to claimable
     */
    function _checkpointUser(address user) internal {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * metaPerCToken) / PRECISION;
        uint256 debt = userMetaDebt[user];
        if (userShare > debt) {
            userClaimableMeta[user] += userShare - debt;
        }
    }
    
    /**
     * @dev Update user debt to current share
     */
    function _updateUserDebt(address user) internal {
        userMetaDebt[user] = (balanceOf(user) * metaPerCToken) / PRECISION;
    }

    /**
    * @notice Checkpoint user's fee accrual
    * @param user Address to checkpoint
    */
    function _checkpointUserFee(address user) internal {
        uint256 userBal = balanceOf(user);
        uint256 userShare = (userBal * feePerCToken) / PRECISION;
        uint256 debt = userFeeDebt[user];
        if (userShare > debt) {
            userClaimableFee[user] += userShare - debt;
        }
}

/**
 * @notice Update user's fee debt to current index
 * @param user Address to update
 */
function _updateUserFeeDebt(address user) internal {
    userFeeDebt[user] = (balanceOf(user) * feePerCToken) / PRECISION;
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
        if (address(emissionsVoteLib) == address(0)) revert NotSet();
        emissionsVoteLib.recordVote(msg.sender, choice, amount / 1e18);
        emit EmissionsVoted(msg.sender, choice, amount);
    }
    
    /**
     * @notice Vote for liquidation
     * @dev V10: Proper CEI - checkpoint and update debt before transfer
     */
    function voteLiquidation(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        uint256 available = unlockedBalanceOf(msg.sender);
        if (available < amount) revert InsufficientUnlockedBalance();
        
        // EFFECTS - Checkpoint META and update debt before transfer
        _checkpointUser(msg.sender);
        _updateUserDebt(msg.sender); 
        
        // Transfer to liquidation contract (not splitter)
        _transfer(msg.sender, liquidation, amount);
        
        // INTERACTIONS - Record in liquidation contract
        IVeAeroLiquidation(liquidation).recordCLock(msg.sender, amount);
        
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
        // Transfer lock check (regular transfers only, not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (amount > unlockedBalanceOf(from)) {
                revert TransferWhileLocked();
            }
        }
        // Checkpoint both parties for META and AERO fee distribution
        if (from != address(0)) {
            _checkpointUser(from);
            _checkpointUserFee(from); 
        }
        if (to != address(0)) {
            _checkpointUser(to);
            _checkpointUserFee(to);  
        }
        
        super._update(from, to, amount);
        
        // Update debts after balance change
        if (from != address(0)) {
            _updateUserDebt(from);
            _updateUserFeeDebt(from);  
        }
        if (to != address(0)) {
            _updateUserDebt(to);
            _updateUserFeeDebt(to);  
        }
        if (from != address(0) && to != address(0) && splitter != address(0)) {
            IVeAeroSplitter(splitter).onCTokenTransfer(from, to, amount);
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
