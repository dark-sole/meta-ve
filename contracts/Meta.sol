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
 * @title Meta V6
 * @notice META token with utilization-based emissions, AERO fee distribution, LP gauge, multi-chain VE
 * @dev Gas optimized, CEI compliant
 * 
 * REWARD SPLITS:
 * - AERO fees (50% from splitter): (1-S) to LP gauge, S to stakers
 * - META incentives (92.2%): (1-S) to stakers, S/2 to VE pools, S/2 to LP gauge
 */
contract Meta is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ════════════════════════════════════════════════════════════════════════
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10000;
    uint64 public constant MAX_CATCHUP_DAYS = 90;
    uint256 public constant MIN_CLAIM = 1e15;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint128 public constant I_INITIAL = 28e15;
    uint64 public constant K_BASE = 2394327123642533;
    uint256 public constant TOKENISYS_BPS = 280;
    uint256 public constant TREASURY_BPS = 500;
    uint256 public constant INCENTIVES_BPS = 9220;
    uint256 public constant EPOCH_DURATION = 7 days;
    
    // ════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ════════════════════════════════════════════════════════════════════════
    
    uint64 public immutable GENESIS_TIME;
    address public immutable TOKENISYS;
    address public immutable TREASURY;
    IERC20 public immutable AERO;
    
    // ════════════════════════════════════════════════════════════════════════
    // PACKED SLOT 0: Core index state (256 bits)
    // ════════════════════════════════════════════════════════════════════════
    
    uint128 public baseIndex;           // 128 bits
    uint64 public lastUpdateDay;        // 64 bits
    uint64 public pendingCatchupDays;   // 64 bits
    
    // ════════════════════════════════════════════════════════════════════════
    // PACKED SLOT 1: Treasury state (256 bits)
    // ════════════════════════════════════════════════════════════════════════
    
    uint128 public treasuryBaselineIndex;  // 128 bits
    uint128 public treasuryAccrued;        // 128 bits
    
    // ════════════════════════════════════════════════════════════════════════
    // PACKED SLOT 2: Fee state (256 bits)
    // ════════════════════════════════════════════════════════════════════════
    
    uint128 public feeRewardIndex;      // 128 bits - AERO fee index for stakers
    uint128 private _reserved;          // 128 bits - future use
    
    // ════════════════════════════════════════════════════════════════════════
    // STATE - SEPARATE SLOTS
    // ════════════════════════════════════════════════════════════════════════
    
    uint256 public totalLockedVotes;
    uint256 public remainingSupply;
    uint256 public accumulatedLPMeta;
    uint256 public accumulatedLPAero;
    
    address public msigTreasury;
    address public splitter;
    address public vToken;
    address public lpPool;
    address public lpGauge;
    bool public lpGaugeLocked;
    
    // ════════════════════════════════════════════════════════════════════════
    // VE POOL STATE
    // ════════════════════════════════════════════════════════════════════════
    
    mapping(address => bool) public isWhitelistedVEPool;
    address[] public vePoolList;
    mapping(address => uint256) public poolVotes;
    mapping(address => uint256) public vePoolChainId;
    /// @dev Packed: [128 bits baseline][128 bits accrued]
    mapping(address => uint256) internal _poolData;
    
    // ════════════════════════════════════════════════════════════════════════
    // USER STATE
    // ════════════════════════════════════════════════════════════════════════
    
    mapping(address => uint256) public userLockedAmount;
    mapping(address => address) public userVotedPool;
    mapping(address => uint256) public userUnlockTime;
    
    /// @dev Packed: [128 bits META baseline][128 bits fee baseline]
    mapping(address => uint256) internal _userBaselines;
    
    mapping(address => uint256) public userAccrued;      // META rewards
    mapping(address => uint256) public userFeeAccrued;   // AERO rewards
    
    // ════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ════════════════════════════════════════════════════════════════════════
    
    event IndexUpdated(uint64 indexed day, uint128 newIndex, uint256 S, uint256 U, uint256 minted);
    event CatchupProgress(uint64 processedDays, uint64 remainingDays);
    event Locked(address indexed user, uint256 amount, address indexed vePool);
    event UnlockInitiated(address indexed user, uint256 amount, uint256 unlockTime);
    event Unlocked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 metaAmount, uint256 aeroAmount);
    event VEPoolClaimed(address indexed vePool, uint256 amount);
    event TreasuryClaimed(address indexed treasury, uint256 amount);
    event VEPoolAdded(address indexed vePool, uint256 chainId);
    event VEPoolRemoved(address indexed vePool);
    event FeesReceived(uint256 amount, uint256 toLPs, uint256 toStakers);
    event PushedToLPGauge(uint256 metaAmount, uint256 aeroAmount);
    event VotePushed(uint256 passiveAmount, uint256 lpPoolAmount);
    
    // ════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ════════════════════════════════════════════════════════════════════════
    
    error ZeroAmount();
    error ZeroAddress();
    error PoolNotWhitelisted();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error PoolHasActiveVotes();
    error CurrentlyUnlocking();
    error NotUnlocking();
    error StillCoolingDown();
    error MustUnlockToChangePool();
    error NothingLocked();
    error NothingToClaim();
    error OnlyMSIG();
    error OnlyPool();
    error OnlySplitter();
    error AlreadySet();
    error LPGaugeIsLocked();
    error VoteWindowNotOpen();
    error LPPoolNotSet();
    error VTokenNotSet();
    
    // ════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ════════════════════════════════════════════════════════════════════════
    
    modifier onlyMSIG() {
        if (msg.sender != msigTreasury) revert OnlyMSIG();
        _;
    }
    
    modifier onlySplitter() {
        if (msg.sender != splitter) revert OnlySplitter();
        _;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ════════════════════════════════════════════════════════════════════════
    
    constructor(
        uint64 genesisTime,
        address tokenisys,
        address treasury,
        address msig,
        address aero
    ) ERC20("Meta", "META") Ownable(msg.sender) {
        if (tokenisys == address(0)) revert ZeroAddress();
        if (treasury == address(0)) revert ZeroAddress();
        if (msig == address(0)) revert ZeroAddress();
        if (aero == address(0)) revert ZeroAddress();
        
        GENESIS_TIME = genesisTime;
        TOKENISYS = tokenisys;
        TREASURY = treasury;
        AERO = IERC20(aero);
        msigTreasury = msig;
        
        baseIndex = I_INITIAL;
        treasuryBaselineIndex = I_INITIAL;
        remainingSupply = TOTAL_SUPPLY;
        
        // Mint 2.8% to Tokenisys
        uint256 tokenisysMint = (TOTAL_SUPPLY * TOKENISYS_BPS) / BPS;
        _mint(tokenisys, tokenisysMint);
        remainingSupply -= tokenisysMint;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // PACKED DATA HELPERS
    // ════════════════════════════════════════════════════════════════════════
    
    function _getPoolData(address pool) internal view returns (uint128 baseline, uint128 accrued) {
        uint256 data = _poolData[pool];
        baseline = uint128(data >> 128);
        accrued = uint128(data);
    }
    
    function _setPoolData(address pool, uint128 baseline, uint128 accrued) internal {
        _poolData[pool] = (uint256(baseline) << 128) | uint256(accrued);
    }
    
    function _getUserBaselines(address user) internal view returns (uint128 metaBaseline, uint128 feeBaseline) {
        uint256 data = _userBaselines[user];
        metaBaseline = uint128(data >> 128);
        feeBaseline = uint128(data);
    }
    
    function _setUserBaselines(address user, uint128 metaBaseline, uint128 feeBaseline) internal {
        _userBaselines[user] = (uint256(metaBaseline) << 128) | uint256(feeBaseline);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // SETUP (MSIG)
    // ════════════════════════════════════════════════════════════════════════
    
    function setSplitter(address _splitter) external onlyMSIG {
        if (_splitter == address(0)) revert ZeroAddress();
        if (splitter != address(0)) revert AlreadySet();
        splitter = _splitter;
    }
    
    function setVToken(address _vToken) external onlyMSIG {
        if (_vToken == address(0)) revert ZeroAddress();
        if (vToken != address(0)) revert AlreadySet();
        vToken = _vToken;
    }
    
    function setLPPool(address _pool) external onlyMSIG {
        if (lpGaugeLocked) revert LPGaugeIsLocked();
        if (_pool == address(0)) revert ZeroAddress();
        lpPool = _pool;
    }
    
    function setLPGauge(address _gauge) external onlyMSIG {
        if (lpGaugeLocked) revert LPGaugeIsLocked();
        if (_gauge == address(0)) revert ZeroAddress();
        lpGauge = _gauge;
    }
    
    function lockLPGauge() external onlyMSIG {
        lpGaugeLocked = true;
    }
    
    function setMSIG(address newMSIG) external onlyMSIG {
        if (newMSIG == address(0)) revert ZeroAddress();
        msigTreasury = newMSIG;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // FEE RECEIVING (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Receive AERO fees from splitter
     * @dev CEI: We trust the amount parameter since onlySplitter
     *      Split: (1-S) to LP gauge, S to stakers
     */
    function receiveFees(uint256 amount) external onlySplitter nonReentrant {
        if (amount == 0) return;
        
        // CHECKS - Calculate split with cached S
        uint256 _totalLocked = totalLockedVotes;  // Cache storage read
        uint256 _remaining = remainingSupply;
        uint256 circulating = TOTAL_SUPPLY - _remaining;
        
        uint256 S;
        if (circulating > 0) {
            S = (_totalLocked * PRECISION) / circulating;
            if (S > PRECISION) S = PRECISION;
        }
        
        uint256 toLPs = (amount * (PRECISION - S)) / PRECISION;
        uint256 toStakers = amount - toLPs;
        
        // EFFECTS - Update state before external call
        accumulatedLPAero += toLPs;
        
        if (toStakers > 0 && _totalLocked > 0) {
            feeRewardIndex += uint128((toStakers * PRECISION) / _totalLocked);
        }
        
        // INTERACTIONS - External call last
        AERO.safeTransferFrom(msg.sender, address(this), amount);
        
        emit FeesReceived(amount, toLPs, toStakers);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // LP GAUGE (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    function _pushToLPGauge() internal {
        address _lpGauge = lpGauge;  // Cache
        if (_lpGauge == address(0)) return;
        
        uint256 metaAmt = accumulatedLPMeta;
        uint256 aeroAmt = accumulatedLPAero;
        
        if (metaAmt == 0 && aeroAmt == 0) return;
        
        // EFFECTS - Clear before external calls
        accumulatedLPMeta = 0;
        accumulatedLPAero = 0;
        
        // INTERACTIONS
        if (metaAmt > 0) {
            _approve(address(this), _lpGauge, metaAmt);
            IGauge(_lpGauge).notifyRewardAmount(address(this), metaAmt);
        }
        
        if (aeroAmt > 0) {
            AERO.approve(_lpGauge, aeroAmt);
            IGauge(_lpGauge).notifyRewardAmount(address(AERO), aeroAmt);
        }
        
        emit PushedToLPGauge(metaAmt, aeroAmt);
    }
    
    function pushToLPGauge() external nonReentrant {
        _pushToLPGauge();
    }
    
    function pushVote() external nonReentrant {
        address _lpPool = lpPool;
        address _vToken = vToken;
        
        if (_lpPool == address(0)) revert LPPoolNotSet();
        if (_vToken == address(0)) revert VTokenNotSet();
        
        // Check voting window (last hour of epoch)
        uint256 epochEnd = ((block.timestamp / EPOCH_DURATION) + 1) * EPOCH_DURATION;
        if (block.timestamp < epochEnd - 1 hours || block.timestamp >= epochEnd) {
            revert VoteWindowNotOpen();
        }
        
        uint256 vBal = IERC20(_vToken).balanceOf(address(this));
        if (vBal == 0) return;
        
        uint256 wholeBal = (vBal / 1e18) * 1e18;
        if (wholeBal == 0) return;
        
        uint256 half = wholeBal >> 1;
        uint256 other = wholeBal - half;
        
        IVToken(_vToken).votePassive(half);
        IVToken(_vToken).vote(_lpPool, other);
        
        emit VotePushed(half, other);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // INDEX UPDATE
    // ════════════════════════════════════════════════════════════════════════
    
    function getCurrentDay() public view returns (uint64) {
        if (block.timestamp < GENESIS_TIME) return 0;
        return uint64((block.timestamp - GENESIS_TIME) / 1 days);
    }
    
    function needsIndexUpdate() external view returns (bool) {
        return getCurrentDay() > lastUpdateDay || pendingCatchupDays > 0;
    }
    
    function getCurrentS() public view returns (uint256) {
        uint256 circulating = TOTAL_SUPPLY - remainingSupply;
        if (circulating == 0) return 0;
        uint256 s = (totalLockedVotes * PRECISION) / circulating;
        return s > PRECISION ? PRECISION : s;
    }
    
    function updateIndex(uint64 maxSteps) public returns (uint64 processedDays, bool complete) {
        uint64 currentDay = getCurrentDay();
        uint64 _lastUpdateDay = lastUpdateDay;  // Cache
        uint64 _pendingDays = pendingCatchupDays;
        
        uint64 totalPending;
        if (_pendingDays > 0) {
            totalPending = _pendingDays;
        } else if (currentDay > _lastUpdateDay) {
            totalPending = currentDay - _lastUpdateDay;
        } else {
            return (0, true);
        }
        
        uint64 limit = maxSteps == 0 ? MAX_CATCHUP_DAYS : maxSteps;
        uint64 daysToProcess = totalPending > limit ? limit : totalPending;
        
        // Cache S for this update
        uint256 S = getCurrentS();
        uint256 U = (4 * S * (PRECISION - S)) / PRECISION;
        
        (uint256 totalMinted, uint128 newIndex) = _processDays(daysToProcess, U);
        
        // Update packed slot 0
        baseIndex = newIndex;
        lastUpdateDay = _lastUpdateDay + daysToProcess;
        pendingCatchupDays = totalPending - daysToProcess;
        
        complete = (pendingCatchupDays == 0 && lastUpdateDay >= currentDay);
        
        // Accumulate S/2 for LP gauge
        if (totalMinted > 0 && S > 0) {
            uint256 incentives = (totalMinted * INCENTIVES_BPS) / BPS;
            uint256 sPortion = (incentives * S) / PRECISION;
            accumulatedLPMeta += sPortion >> 1;
        }
        
        _pushToLPGauge();
        
        emit IndexUpdated(lastUpdateDay, newIndex, S, U, totalMinted);
        
        if (pendingCatchupDays > 0) {
            emit CatchupProgress(daysToProcess, pendingCatchupDays);
        }
        
        return (daysToProcess, complete);
    }
    
    function updateIndex() external returns (uint64, bool) {
        return updateIndex(0);
    }
    
    function _processDays(uint64 daysToProcess, uint256 U) internal returns (uint256 totalMinted, uint128 newIndex) {
        uint128 P = baseIndex;
        uint256 _remainingSupply = remainingSupply;  // Cache
        
        for (uint64 i = 0; i < daysToProcess; ) {
            uint256 oneMinusP = PRECISION - uint256(P);
            uint256 baseDelta = (uint256(P) * oneMinusP * uint256(K_BASE)) / (PRECISION * PRECISION);
            
            if (baseDelta == 0) break;
            
            uint256 adjustedDelta = (baseDelta * U) / PRECISION;
            uint256 tokensToMint = (TOTAL_SUPPLY * adjustedDelta) / PRECISION;
            
            if (tokensToMint > _remainingSupply) {
                tokensToMint = _remainingSupply;
            }
            
            if (tokensToMint > 0) {
                _mint(address(this), tokensToMint);
                _remainingSupply -= tokensToMint;
                totalMinted += tokensToMint;
            }
            
            P = uint128(uint256(P) + adjustedDelta);
            if (P >= uint128(PRECISION)) {
                P = uint128(PRECISION);
                break;
            }
            
            unchecked { ++i; }
        }
        
        remainingSupply = _remainingSupply;  // Write back
        newIndex = P;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // STAKING (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    function lockAndVote(uint256 amount, address vePool) external nonReentrant {
        // CHECKS
        if (amount == 0) revert ZeroAmount();
        if (!isWhitelistedVEPool[vePool]) revert PoolNotWhitelisted();
        if (userUnlockTime[msg.sender] != 0) revert CurrentlyUnlocking();
        
        uint256 existingLock = userLockedAmount[msg.sender];
        if (existingLock > 0 && userVotedPool[msg.sender] != vePool) {
            revert MustUnlockToChangePool();
        }
        
        // Ensure index current
        _ensureIndexUpdated();
        
        // EFFECTS - Checkpoint and update state
        _checkpointUser(msg.sender);
        
        if (existingLock == 0) {
            _setUserBaselines(msg.sender, baseIndex, feeRewardIndex);
        }
        
        userLockedAmount[msg.sender] = existingLock + amount;
        userVotedPool[msg.sender] = vePool;
        
        // Update pool
        _checkpointPool(vePool);
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        if (poolBase == 0) {
            _setPoolData(vePool, baseIndex, poolAcc);
        }
        poolVotes[vePool] += amount;
        totalLockedVotes += amount;
        
        // INTERACTIONS
        _transfer(msg.sender, address(this), amount);
        
        emit Locked(msg.sender, amount, vePool);
    }
    
    function initiateUnlock() external nonReentrant {
        // CHECKS
        uint256 amount = userLockedAmount[msg.sender];
        if (amount == 0) revert NothingLocked();
        if (userUnlockTime[msg.sender] != 0) revert CurrentlyUnlocking();
        
        _ensureIndexUpdated();
        
        // EFFECTS
        _checkpointUser(msg.sender);
        _checkpointPool(userVotedPool[msg.sender]);
        
        uint256 unlockTime = ((block.timestamp / 1 days) * 1 days) + 2 days + 1 minutes;
        userUnlockTime[msg.sender] = unlockTime;
        
        emit UnlockInitiated(msg.sender, amount, unlockTime);
    }
    
    function completeUnlock() external nonReentrant {
        // CHECKS
        uint256 unlockTime = userUnlockTime[msg.sender];
        if (unlockTime == 0) revert NotUnlocking();
        if (block.timestamp < unlockTime) revert StillCoolingDown();
        
        _ensureIndexUpdated();
        
        uint256 amount = userLockedAmount[msg.sender];
        address vePool = userVotedPool[msg.sender];
        
        // EFFECTS
        _checkpointUser(msg.sender);
        _checkpointPool(vePool);
        
        poolVotes[vePool] -= amount;
        totalLockedVotes -= amount;
        
        userLockedAmount[msg.sender] = 0;
        userVotedPool[msg.sender] = address(0);
        userUnlockTime[msg.sender] = 0;
        _setUserBaselines(msg.sender, 0, 0);
        
        // INTERACTIONS
        _transfer(address(this), msg.sender, amount);
        
        emit Unlocked(msg.sender, amount);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // CHECKPOINTS (Internal)
    // ════════════════════════════════════════════════════════════════════════
    
    function _ensureIndexUpdated() internal {
        if (getCurrentDay() > lastUpdateDay || pendingCatchupDays > 0) {
            updateIndex(0);
        }
    }
    
    function _checkpointUser(address user) internal {
        uint256 locked = userLockedAmount[user];
        if (locked == 0) return;
        
        uint256 _totalLocked = totalLockedVotes;
        if (_totalLocked == 0) return;
        
        (uint128 metaBase, uint128 feeBase) = _getUserBaselines(user);
        if (metaBase == 0) metaBase = I_INITIAL;
        
        uint128 _baseIndex = baseIndex;
        uint128 _feeIndex = feeRewardIndex;
        
        // META rewards: (1-S) portion
        if (_baseIndex > metaBase) {
            uint256 deltaIndex = uint256(_baseIndex) - uint256(metaBase);
            uint256 S = getCurrentS();
            uint256 oneMinusS = PRECISION - S;
            uint256 incentivesDelta = (deltaIndex * INCENTIVES_BPS) / BPS;
            uint256 stakerPortion = (incentivesDelta * oneMinusS) / PRECISION;
            uint256 userShare = (stakerPortion * locked) / _totalLocked;
            userAccrued[user] += (TOTAL_SUPPLY * userShare) / PRECISION;
        }
        
        // AERO fee rewards
        if (_feeIndex > feeBase) {
            uint256 feeDelta = uint256(_feeIndex) - uint256(feeBase);
            userFeeAccrued[user] += (feeDelta * locked) / PRECISION;
        }
        
        _setUserBaselines(user, _baseIndex, _feeIndex);
    }
    
    function _checkpointPool(address vePool) internal {
        if (!isWhitelistedVEPool[vePool]) return;
        
        uint256 _totalLocked = totalLockedVotes;
        uint256 votes = poolVotes[vePool];
        if (_totalLocked == 0 || votes == 0) return;
        
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        if (poolBase == 0) poolBase = I_INITIAL;
        
        uint128 _baseIndex = baseIndex;
        if (_baseIndex <= poolBase) return;
        
        uint256 deltaIndex = uint256(_baseIndex) - uint256(poolBase);
        
        // S/2 portion for VE pools
        uint256 S = getCurrentS();
        uint256 incentivesDelta = (deltaIndex * INCENTIVES_BPS) / BPS;
        uint256 sPortion = (incentivesDelta * S) / PRECISION;
        uint256 vePoolPortion = sPortion >> 1;
        
        uint256 poolShare = (vePoolPortion * votes) / _totalLocked;
        uint256 poolTokens = (TOTAL_SUPPLY * poolShare) / PRECISION;
        
        _setPoolData(vePool, _baseIndex, poolAcc + uint128(poolTokens));
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // CLAIMS (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Claim both META and AERO rewards
     */
    function claimRewards() external nonReentrant returns (uint256 metaAmt, uint256 aeroAmt) {
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        
        // EFFECTS
        metaAmt = userAccrued[msg.sender];
        aeroAmt = userFeeAccrued[msg.sender];
        
        if (metaAmt > 0) {
            uint256 avail = balanceOf(address(this));
            if (metaAmt > avail) metaAmt = avail;
            userAccrued[msg.sender] = 0;
        }
        
        if (aeroAmt > 0) {
            uint256 aeroAvail = AERO.balanceOf(address(this)) - accumulatedLPAero;
            if (aeroAmt > aeroAvail) aeroAmt = aeroAvail;
            userFeeAccrued[msg.sender] = 0;
        }
        
        // INTERACTIONS
        if (metaAmt > 0) {
            _transfer(address(this), msg.sender, metaAmt);
        }
        if (aeroAmt > 0) {
            AERO.safeTransfer(msg.sender, aeroAmt);
        }
        
        emit RewardsClaimed(msg.sender, metaAmt, aeroAmt);
    }
    
    /**
     * @notice Backward compatible claim (returns META only)
     */
    function claimStakerRewards() external nonReentrant returns (uint256 amount) {
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        
        amount = userAccrued[msg.sender];
        if (amount == 0 || amount < MIN_CLAIM) revert NothingToClaim();
        
        uint256 avail = balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        // EFFECTS
        userAccrued[msg.sender] = 0;
        
        uint256 aeroAmt = userFeeAccrued[msg.sender];
        if (aeroAmt > 0) {
            uint256 aeroAvail = AERO.balanceOf(address(this)) - accumulatedLPAero;
            if (aeroAmt > aeroAvail) aeroAmt = aeroAvail;
            userFeeAccrued[msg.sender] = 0;
        }
        
        // INTERACTIONS
        _transfer(address(this), msg.sender, amount);
        if (aeroAmt > 0) {
            AERO.safeTransfer(msg.sender, aeroAmt);
        }
        
        emit RewardsClaimed(msg.sender, amount, aeroAmt);
    }
    
    /**
     * @notice VE pool claims its META allocation (S/2 portion)
     */
    function claimForVEPool() external nonReentrant returns (uint256 amount) {
        address vePool = msg.sender;
        
        // CHECKS
        if (!isWhitelistedVEPool[vePool]) revert OnlyPool();
        
        _ensureIndexUpdated();
        _checkpointPool(vePool);
        
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        amount = uint256(poolAcc);
        if (amount == 0) return 0;
        
        uint256 avail = balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        // EFFECTS
        _setPoolData(vePool, poolBase, 0);
        
        // INTERACTIONS
        _transfer(address(this), vePool, amount);
        
        emit VEPoolClaimed(vePool, amount);
    }
    
    function claimTreasury() external nonReentrant returns (uint256 amount) {
        _ensureIndexUpdated();
        
        // Checkpoint treasury
        uint128 _baseIndex = baseIndex;
        if (_baseIndex > treasuryBaselineIndex) {
            uint256 deltaIndex = uint256(_baseIndex) - uint256(treasuryBaselineIndex);
            uint256 treasuryShare = (deltaIndex * TREASURY_BPS) / BPS;
            treasuryAccrued += uint128((TOTAL_SUPPLY * treasuryShare) / PRECISION);
            treasuryBaselineIndex = _baseIndex;
        }
        
        amount = uint256(treasuryAccrued);
        if (amount == 0) return 0;
        
        uint256 avail = balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        // EFFECTS
        treasuryAccrued = 0;
        
        // INTERACTIONS
        _transfer(address(this), TREASURY, amount);
        
        emit TreasuryClaimed(TREASURY, amount);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // VE POOL MANAGEMENT
    // ════════════════════════════════════════════════════════════════════════
    
    function addVEPool(address vePool, uint256 chainId) external onlyMSIG {
        if (vePool == address(0)) revert ZeroAddress();
        if (isWhitelistedVEPool[vePool]) revert AlreadyWhitelisted();
        
        isWhitelistedVEPool[vePool] = true;
        vePoolList.push(vePool);
        vePoolChainId[vePool] = chainId;
        _setPoolData(vePool, baseIndex, 0);
        
        emit VEPoolAdded(vePool, chainId);
    }
    
    function addVEPool(address vePool) external onlyMSIG {
        if (vePool == address(0)) revert ZeroAddress();
        if (isWhitelistedVEPool[vePool]) revert AlreadyWhitelisted();
        
        isWhitelistedVEPool[vePool] = true;
        vePoolList.push(vePool);
        vePoolChainId[vePool] = block.chainid;
        _setPoolData(vePool, baseIndex, 0);
        
        emit VEPoolAdded(vePool, block.chainid);
    }
    
    function removeVEPool(address vePool) external onlyMSIG {
        if (!isWhitelistedVEPool[vePool]) revert NotWhitelisted();
        if (poolVotes[vePool] > 0) revert PoolHasActiveVotes();
        
        isWhitelistedVEPool[vePool] = false;
        
        uint256 len = vePoolList.length;
        for (uint256 i = 0; i < len; ) {
            if (vePoolList[i] == vePool) {
                vePoolList[i] = vePoolList[len - 1];
                vePoolList.pop();
                break;
            }
            unchecked { ++i; }
        }
        
        emit VEPoolRemoved(vePool);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════
    
    function getVEPools() external view returns (address[] memory) {
        return vePoolList;
    }
    
    function getUserInfo(address user) external view returns (
        uint256 lockedAmount,
        address votedPool,
        uint256 unlockTime,
        uint256 pendingMeta,
        uint256 pendingAero
    ) {
        lockedAmount = userLockedAmount[user];
        votedPool = userVotedPool[user];
        unlockTime = userUnlockTime[user];
        pendingMeta = userAccrued[user];
        pendingAero = userFeeAccrued[user];
        
        if (lockedAmount > 0 && totalLockedVotes > 0) {
            (uint128 metaBase, uint128 feeBase) = _getUserBaselines(user);
            if (metaBase == 0) metaBase = I_INITIAL;
            
            if (baseIndex > metaBase) {
                uint256 deltaIndex = uint256(baseIndex) - uint256(metaBase);
                uint256 S = getCurrentS();
                uint256 incentivesDelta = (deltaIndex * INCENTIVES_BPS) / BPS;
                uint256 stakerPortion = (incentivesDelta * (PRECISION - S)) / PRECISION;
                uint256 userShare = (stakerPortion * lockedAmount) / totalLockedVotes;
                pendingMeta += (TOTAL_SUPPLY * userShare) / PRECISION;
            }
            
            if (feeRewardIndex > feeBase) {
                uint256 feeDelta = uint256(feeRewardIndex) - uint256(feeBase);
                pendingAero += (feeDelta * lockedAmount) / PRECISION;
            }
        }
    }
    
    function getPoolInfo(address vePool) external view returns (
        bool whitelisted,
        uint256 votes,
        uint256 pendingRewards,
        uint256 chainId
    ) {
        whitelisted = isWhitelistedVEPool[vePool];
        votes = poolVotes[vePool];
        chainId = vePoolChainId[vePool];
        
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        pendingRewards = uint256(poolAcc);
        
        if (whitelisted && totalLockedVotes > 0 && votes > 0) {
            if (poolBase == 0) poolBase = I_INITIAL;
            
            if (baseIndex > poolBase) {
                uint256 deltaIndex = uint256(baseIndex) - uint256(poolBase);
                uint256 S = getCurrentS();
                uint256 incentivesDelta = (deltaIndex * INCENTIVES_BPS) / BPS;
                uint256 sPortion = (incentivesDelta * S) / PRECISION;
                uint256 vePoolPortion = sPortion >> 1;
                uint256 poolShare = (vePoolPortion * votes) / totalLockedVotes;
                pendingRewards += (TOTAL_SUPPLY * poolShare) / PRECISION;
            }
        }
    }
    
    function getCatchupStatus() external view returns (
        uint64 currentDay_,
        uint64 lastUpdated,
        uint64 pendingDays,
        bool needsUpdate
    ) {
        currentDay_ = getCurrentDay();
        lastUpdated = lastUpdateDay;
        pendingDays = pendingCatchupDays;
        if (pendingDays == 0 && currentDay_ > lastUpdated) {
            pendingDays = currentDay_ - lastUpdated;
        }
        needsUpdate = pendingDays > 0;
    }
    
    function getLPGaugeInfo() external view returns (
        address pool,
        address gauge,
        bool locked,
        uint256 pendingMeta,
        uint256 pendingAero
    ) {
        return (lpPool, lpGauge, lpGaugeLocked, accumulatedLPMeta, accumulatedLPAero);
    }
    
    // Legacy view functions for compatibility
    function userBaselineIndex(address user) external view returns (uint128) {
        (uint128 metaBase, ) = _getUserBaselines(user);
        return metaBase;
    }
    
    function userFeeBaseline(address user) external view returns (uint128) {
        (, uint128 feeBase) = _getUserBaselines(user);
        return feeBase;
    }
    
    function poolBaselineIndex(address pool) external view returns (uint128) {
        (uint128 baseline, ) = _getPoolData(pool);
        return baseline;
    }
    
    function poolAccrued(address pool) external view returns (uint256) {
        (, uint128 accrued) = _getPoolData(pool);
        return uint256(accrued);
    }
}
