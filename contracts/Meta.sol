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
 * @title Meta V.DELTA
 * @notice META token with utilization-based emissions, multi-VE support
 * @dev Gas optimized, CEI compliant
 * 
 * FEE DISTRIBUTION (local fees only - AERO on Base):
 * Phase 1 (multiVEEnabled = false):
 * - 50% → C-AERO holders (poolFeeAccrued)
 * - 50% × S → META stakers (feeRewardIndex)
 * - 50% × (1-S) → C-AERO holders (poolFeeAccrued)
 * 
 * Phase 2 (multiVEEnabled = true):
 * - 50% → C-AERO holders (poolFeeAccrued)
 * - 50% × S → META stakers (feeRewardIndex)
 * - 50% × (1-S) × VOTE_AERO → C-AERO holders (poolFeeAccrued)
 * - 50% × (1-S) × (1-VOTE_AERO) → FeeContract (for remote C-tokens)
 * 
 * META EMISSIONS (95% of minted):
 * - 5% → Treasury
 * - (1-S) × 95% → META stakers (on Base)
 * - S/2 × 95% → C-tokens:
 *   - Phase 1: 100% to C-AERO (poolAccrued)
 *   - Phase 2: VOTE_AERO to C-AERO, rest to FeeContract
 * - S/2 × 95% → LP incentives:
 *   - Phase 1: 100% to META-AERO LP gauge
 *   - Phase 2: VOTE_AERO to META-AERO LP gauge, rest to FeeContract
 * 
 * MULTI-CHAIN MODEL:
 * - Fees stay local (each chain distributes native VE token)
 * - META emissions: local via poolAccrued, remote via FeeContract
 * - FeeContract handles its own indexation for remote C-tokens
 * - Staking/voting only on Base
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
    uint256 public constant LOCAL_CHAIN_ID = 8453; // Base mainnet
    
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
    uint256 public totalUnlocking;
    
    address public msigTreasury;
    address public splitter;
    address public vToken;
    address public lpPool;              // Primary LP pool for voting (META-AERO)
    
    // ════════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN STATE
    // ════════════════════════════════════════════════════════════════════════
    
    address public l1ProofVerifier;                         // For verifying remote claims
    mapping(uint256 => bool) public isWhitelistedChain;     // chainId => whitelisted
    uint256[] public chainList;                             // List of remote chain IDs

    bool public l1ProofVerifierChangeable;
    
    // ════════════════════════════════════════════════════════════════════════
    // MULTI-VE STATE
    // ════════════════════════════════════════════════════════════════════════
    
    bool public multiVEEnabled;         // One-way flag for Phase 2
    address public feeContract;         // FeeDistributor for remote C-token fees and LP incentives
    
    // ════════════════════════════════════════════════════════════════════════
    // VE POOL STATE
    // ════════════════════════════════════════════════════════════════════════
    
    mapping(address => bool) public isWhitelistedVEPool;
    address[] public vePoolList;
    mapping(address => uint256) public poolVotes;
    mapping(address => uint256) public vePoolChainId;
    /// @dev Packed: [128 bits baseline][128 bits accrued]
    mapping(address => uint256) internal _poolData;
    
    /// @dev Per-pool LP gauge (only meaningful for local pools)
    mapping(address => address) public poolLPGauge;
    /// @dev META emissions accrued for LP incentives
    mapping(address => uint256) public poolLPAccruedMeta;
    
    /// @dev Fee accumulator for C-token holders (local AERO fees only)
    mapping(address => uint256) public poolFeeAccrued;    // vePool => AERO fees for C-token
    
    // ════════════════════════════════════════════════════════════════════════
    // USER STATE
    // ════════════════════════════════════════════════════════════════════════
    
    mapping(address => uint256) public userLockedAmount;
    mapping(address => address) public userVotedPool;
    mapping(address => uint256) public userUnlockTime;
    mapping(address => uint256) public userUnlockingAmount;
    
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
    event VEPoolFeesClaimed(address indexed vePool, uint256 amount);
    event TreasuryClaimed(address indexed treasury, uint256 amount);
    event VEPoolAdded(address indexed vePool, uint256 chainId, address lpGauge);
    event VEPoolRemoved(address indexed vePool);
    event LPGaugeUpdated(address indexed vePool, address indexed lpGauge);
    event FeesReceived(uint256 amount, uint256 toCToken, uint256 toStakers, uint256 toFeeContract);
    event CTokenIncentivesDistributed(uint256 toLocalPool, uint256 toFeeContract);
    event LPIncentivesDistributed(uint256 toLocalGauge, uint256 toFeeContract);
    event PushedToLPGauge(address indexed vePool, uint256 metaAmount);
    event VotePushed(uint256 passiveAmount, uint256 lpPoolAmount);
    event ChainWhitelisted(uint256 indexed chainId);
    event ChainRemoved(uint256 indexed chainId);
    event L1ProofVerifierSet(address indexed verifier);
    event L1ProofAuthorityRenounced();
    event FeeContractSet(address indexed feeContract);
    event MultiVEEnabled();
    event SplitterUpdated(address indexed newSplitter);
    event MSIGUpdated(address indexed newMSIG);
    
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
    error VoteWindowNotOpen();
    error LPPoolNotSet();
    error VTokenNotSet();
    error ExceedsAvailable();
    error LPGaugeNotSet();
    error ChainNotWhitelisted();
    error ChainAlreadyWhitelisted();
    error NotLocalPool();
    error InvalidChainId();
    error L1ProofAuthorityAlreadyRenounced();
    error MultiVEAlreadyEnabled();
    error FeeContractNotSet();
    
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

        l1ProofVerifierChangeable = true;
        multiVEEnabled = false;
        
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
        emit SplitterUpdated(_splitter);
    }
    
    function setVToken(address _vToken) external onlyMSIG {
        if (_vToken == address(0)) revert ZeroAddress();
        if (vToken != address(0)) revert AlreadySet();
        vToken = _vToken;
    }
    
    function setLPPool(address _pool) external onlyMSIG {
        if (_pool == address(0)) revert ZeroAddress();
        lpPool = _pool;
    }
    
    function setPoolLPGauge(address vePool, address lpGauge_) external onlyMSIG {
        if (!isWhitelistedVEPool[vePool]) revert NotWhitelisted();
        if (lpGauge_ == address(0)) revert ZeroAddress();
        poolLPGauge[vePool] = lpGauge_;
        emit LPGaugeUpdated(vePool, lpGauge_);
    }
    
    function setMSIG(address newMSIG) external onlyMSIG {
        if (newMSIG == address(0)) revert ZeroAddress();
        msigTreasury = newMSIG;
        emit MSIGUpdated(newMSIG);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN SETUP (MSIG)
    // ════════════════════════════════════════════════════════════════════════
    
    function renounceL1ProofAuthority() external onlyMSIG {
        if (!l1ProofVerifierChangeable) revert L1ProofAuthorityAlreadyRenounced();
        if (l1ProofVerifier == address(0)) revert ZeroAddress();
        l1ProofVerifierChangeable = false;
        emit L1ProofAuthorityRenounced();
    }

    function setL1ProofVerifier(address _verifier) external onlyMSIG {
        if (_verifier == address(0)) revert ZeroAddress();
        if (!l1ProofVerifierChangeable) revert L1ProofAuthorityAlreadyRenounced();
        l1ProofVerifier = _verifier;
        emit L1ProofVerifierSet(_verifier);
    }
    
    function whitelistChain(uint256 chainId) external onlyMSIG {
        if (chainId == LOCAL_CHAIN_ID) revert InvalidChainId();
        if (isWhitelistedChain[chainId]) revert ChainAlreadyWhitelisted();
        
        isWhitelistedChain[chainId] = true;
        chainList.push(chainId);
        
        emit ChainWhitelisted(chainId);
    }
    
    function removeChain(uint256 chainId) external onlyMSIG {
        if (!isWhitelistedChain[chainId]) revert ChainNotWhitelisted();
        
        isWhitelistedChain[chainId] = false;
        
        uint256 len = chainList.length;
        for (uint256 i = 0; i < len; ) {
            if (chainList[i] == chainId) {
                chainList[i] = chainList[len - 1];
                chainList.pop();
                break;
            }
            unchecked { ++i; }
        }
        
        emit ChainRemoved(chainId);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // MULTI-VE SETUP (MSIG)
    // ════════════════════════════════════════════════════════════════════════
    
    function setFeeContract(address _feeContract) external onlyMSIG {
        if (_feeContract == address(0)) revert ZeroAddress();
        feeContract = _feeContract;
        emit FeeContractSet(_feeContract);
    }
    
    function enableMultiVE() external onlyMSIG {
        if (multiVEEnabled) revert MultiVEAlreadyEnabled();
        if (feeContract == address(0)) revert FeeContractNotSet();
        multiVEEnabled = true;
        emit MultiVEEnabled();
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // FEE RECEIVING (LOCAL ONLY - CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Receive AERO fees from local splitter
     * @dev Distribution depends on multiVEEnabled flag:
     *      Phase 1: 50% C-token, 50%×S stakers, 50%×(1-S) C-token
     *      Phase 2: 50% C-token, 50%×S stakers, 50%×(1-S)×VOTE_AERO C-token, rest to feeContract
     */
    function receiveFees(uint256 amount) external onlySplitter nonReentrant {
        if (amount == 0) return;
        
        // Get local VE pool (C-AERO on Base)
        address localPool = _getLocalVEPool();
        if (localPool == address(0)) {
            // No local pool configured, send all to stakers
            if (totalLockedVotes > 0) {
                feeRewardIndex += uint128((amount * PRECISION) / totalLockedVotes);
            }
            AERO.safeTransferFrom(msg.sender, address(this), amount);
            emit FeesReceived(amount, 0, amount, 0);
            return;
        }
        
        // CHECKS - Calculate split
        uint256 S = getCurrentS();
        
        uint256 toCToken = amount / 2;                       // 50%
        uint256 remaining = amount - toCToken;               // 50%
        uint256 toStakers = (remaining * S) / PRECISION;     // 50% × S
        uint256 veShare = remaining - toStakers;             // 50% × (1-S)
        
        // EFFECTS
        poolFeeAccrued[localPool] += toCToken;
        
        if (toStakers > 0 && totalLockedVotes > 0) {
            feeRewardIndex += uint128((toStakers * PRECISION) / totalLockedVotes);
        }
        
        uint256 toFeeContract = 0;
        
        if (multiVEEnabled && veShare > 0) {
            // Phase 2: Split veShare by vote weight
            uint256 aeroVotes = poolVotes[localPool];
            uint256 _totalLocked = totalLockedVotes;
            
            if (_totalLocked > 0 && aeroVotes > 0) {
                uint256 toCTokenFromVE = (veShare * aeroVotes) / _totalLocked;
                toFeeContract = veShare - toCTokenFromVE;
                poolFeeAccrued[localPool] += toCTokenFromVE;
            } else {
                // No votes, all to feeContract
                toFeeContract = veShare;
            }
        } else {
            // Phase 1: All veShare to C-AERO
            poolFeeAccrued[localPool] += veShare;
        }
        
        // INTERACTIONS
        AERO.safeTransferFrom(msg.sender, address(this), amount);
        
        if (toFeeContract > 0) {
            AERO.safeTransfer(feeContract, toFeeContract);
        }
        
        emit FeesReceived(amount, toCToken + (veShare - toFeeContract), toStakers, toFeeContract);
    }
    
    /**
     * @notice Get the local (Base chain) VE pool
     */
    function _getLocalVEPool() internal view returns (address) {
        uint256 len = vePoolList.length;
        for (uint256 i = 0; i < len; ) {
            address pool = vePoolList[i];
            if (vePoolChainId[pool] == LOCAL_CHAIN_ID) {
                return pool;
            }
            unchecked { ++i; }
        }
        return address(0);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // LP GAUGE (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Push accrued META to LP gauge
     * @dev Only pushes to local gauges. META only (no AERO).
     */
    function _pushToLPGauge(address vePool) internal {
        // Only push to local gauges from this contract
        if (vePoolChainId[vePool] != LOCAL_CHAIN_ID) return;
        
        address gauge = poolLPGauge[vePool];
        if (gauge == address(0)) return;
        
        uint256 metaAmt = poolLPAccruedMeta[vePool];
        if (metaAmt == 0) return;
        
        // EFFECTS
        poolLPAccruedMeta[vePool] = 0;
        
        // INTERACTIONS
        _approve(address(this), gauge, metaAmt);
        IGauge(gauge).notifyRewardAmount(address(this), metaAmt);
        
        emit PushedToLPGauge(vePool, metaAmt);
    }
    
    function _pushAllLocalLPGauges() internal {
        uint256 len = vePoolList.length;
        for (uint256 i = 0; i < len; ) {
            address pool = vePoolList[i];
            if (vePoolChainId[pool] == LOCAL_CHAIN_ID) {
                _pushToLPGauge(pool);
            }
            unchecked { ++i; }
        }
    }
    
    function pushToLPGauge(address vePool) external nonReentrant {
        if (!isWhitelistedVEPool[vePool]) revert NotWhitelisted();
        if (vePoolChainId[vePool] != LOCAL_CHAIN_ID) revert NotLocalPool();
        _pushToLPGauge(vePool);
    }
    
    function pushAllLPGauges() external nonReentrant {
        _pushAllLocalLPGauges();
    }
    
    function pushVote() external nonReentrant {
        address _lpPool = lpPool;
        address _vToken = vToken;
        
        if (_vToken == address(0)) revert VTokenNotSet();
        
        uint256 epochEnd = ((block.timestamp / EPOCH_DURATION) + 1) * EPOCH_DURATION;

        if (block.timestamp < epochEnd - 3 hours || block.timestamp >= epochEnd - 2 hours) {
            revert VoteWindowNotOpen();
        }
        
        uint256 vBal = IERC20(_vToken).balanceOf(address(this));
        if (vBal == 0) return;
        
        uint256 wholeBal = (vBal / 1e18) * 1e18;
        if (wholeBal == 0) return;

        if (_lpPool == address(0)) {
            // No LP pool - vote 100% passive
            IVToken(_vToken).votePassive(wholeBal);
            emit VotePushed(wholeBal, 0);
            } else {
                // LP pool set - vote 50/50
                uint256 half = wholeBal >> 1;
                uint256 other = wholeBal - half;
                IVToken(_vToken).votePassive(half);
                IVToken(_vToken).vote(_lpPool, other);
                emit VotePushed(half, other);
        }
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
        uint64 _lastUpdateDay = lastUpdateDay;
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
        
        uint256 S = getCurrentS();
        uint256 U = (4 * S * (PRECISION - S)) / PRECISION;
        
        (uint256 totalMinted, uint128 newIndex) = _processDays(daysToProcess, U);
        
        baseIndex = newIndex;
        lastUpdateDay = _lastUpdateDay + daysToProcess;
        pendingCatchupDays = totalPending - daysToProcess;
        
        complete = (pendingCatchupDays == 0 && lastUpdateDay >= currentDay);
        
        // Distribute S/2 C-token incentives
        _distributeCTokenIncentives(totalMinted, S);
        
        // Distribute S/2 LP incentives
        _distributeLPIncentives(totalMinted, S);
        
        // Push to local gauges
        _pushAllLocalLPGauges();
        
        emit IndexUpdated(lastUpdateDay, newIndex, S, U, totalMinted);
        
        if (pendingCatchupDays > 0) {
            emit CatchupProgress(daysToProcess, pendingCatchupDays);
        }
        
        return (daysToProcess, complete);
    }
    
    /**
     * @notice Distribute S/2 portion of emissions to C-tokens
     * @dev Phase 1: All to local C-AERO (poolAccrued)
     *      Phase 2: VOTE_AERO to local C-AERO, rest to feeContract
     */
    function _distributeCTokenIncentives(uint256 totalMinted, uint256 S) internal {
        if (totalMinted == 0 || S == 0) return;
        
        uint256 incentives = (totalMinted * INCENTIVES_BPS) / BPS;
        uint256 sPortion = (incentives * S) / PRECISION;
        uint256 cTokenPortion = sPortion >> 1;  // S/2
        
        if (cTokenPortion == 0) return;
        
        address localPool = _getLocalVEPool();
        uint256 _totalLocked = totalLockedVotes;
        
        if (_totalLocked == 0) return;
        
        uint256 toLocalPool = 0;
        uint256 toFeeContract = 0;
        
        if (multiVEEnabled) {
            // Phase 2: Split by vote weight
            uint256 localVotes = localPool != address(0) ? poolVotes[localPool] : 0;
            
            if (localVotes > 0) {
                toLocalPool = (cTokenPortion * localVotes) / _totalLocked;
            }
            toFeeContract = cTokenPortion - toLocalPool;
        } else {
            // Phase 1: All to local C-token
            toLocalPool = cTokenPortion;
        }
        
        // EFFECTS
        if (toLocalPool > 0 && localPool != address(0)) {
            (uint128 poolBase, uint128 poolAcc) = _getPoolData(localPool);
            _setPoolData(localPool, baseIndex, poolAcc + uint128(toLocalPool));
        }
        
        // INTERACTIONS
        if (toFeeContract > 0) {
            _transfer(address(this), feeContract, toFeeContract);
        }
        
        emit CTokenIncentivesDistributed(toLocalPool, toFeeContract);
    }
    
    /**
     * @notice Distribute S/2 portion of emissions to LP incentives
     * @dev Phase 1: All to local LP gauge
     *      Phase 2: VOTE_AERO to local LP gauge, rest to feeContract
     */
    function _distributeLPIncentives(uint256 totalMinted, uint256 S) internal {
        if (totalMinted == 0 || S == 0) return;
        
        uint256 incentives = (totalMinted * INCENTIVES_BPS) / BPS;
        uint256 sPortion = (incentives * S) / PRECISION;
        uint256 lpPortion = sPortion >> 1;
        
        if (lpPortion == 0) return;
        
        address localPool = _getLocalVEPool();
        uint256 _totalLocked = totalLockedVotes;
        
        if (_totalLocked == 0) return;
        
        uint256 toLocalGauge = 0;
        uint256 toFeeContract = 0;
        
        if (multiVEEnabled) {
            // Phase 2: Split by vote weight
            uint256 localVotes = localPool != address(0) ? poolVotes[localPool] : 0;
            
            if (localVotes > 0) {
                toLocalGauge = (lpPortion * localVotes) / _totalLocked;
            }
            toFeeContract = lpPortion - toLocalGauge;
        } else {
            // Phase 1: All to local LP
            toLocalGauge = lpPortion;
        }
        
        // EFFECTS
        if (toLocalGauge > 0 && localPool != address(0)) {
            poolLPAccruedMeta[localPool] += toLocalGauge;
        }
        
        // INTERACTIONS
        if (toFeeContract > 0) {
            _transfer(address(this), feeContract, toFeeContract);
        }
        
        emit LPIncentivesDistributed(toLocalGauge, toFeeContract);
    }
    
    function updateIndex() external returns (uint64, bool) {
        return updateIndex(0);
    }
    
    function _processDays(uint64 daysToProcess, uint256 U) internal returns (uint256 totalMinted, uint128 newIndex) {
        uint128 P = baseIndex;
        uint256 _remainingSupply = remainingSupply;
        
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
        
        remainingSupply = _remainingSupply;
        newIndex = P;
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // STAKING (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    function lockAndVote(uint256 amount, address vePool) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!isWhitelistedVEPool[vePool]) revert PoolNotWhitelisted();
        
        uint256 existingLock = userLockedAmount[msg.sender];
        if (existingLock > 0 && userVotedPool[msg.sender] != vePool) {
            revert MustUnlockToChangePool();
        }
        
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        
        if (existingLock == 0) {
            _setUserBaselines(msg.sender, baseIndex, feeRewardIndex);
        }
        
        userLockedAmount[msg.sender] = existingLock + amount;
        userVotedPool[msg.sender] = vePool;
        
        _syncPoolBaseline(vePool);
        poolVotes[vePool] += amount;
        totalLockedVotes += amount;
        
        _transfer(msg.sender, address(this), amount);
        
        emit Locked(msg.sender, amount, vePool);
    }
    
    function initiateUnlock(uint256 amount) external nonReentrant {
        uint256 locked = userLockedAmount[msg.sender];
        uint256 alreadyUnlocking = userUnlockingAmount[msg.sender];
        
        if (amount == 0) revert ZeroAmount();
        if (locked == 0) revert NothingLocked();
        if (userUnlockTime[msg.sender] != 0) revert CurrentlyUnlocking();
        if (amount > locked - alreadyUnlocking) revert ExceedsAvailable();
        
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        _syncPoolBaseline(userVotedPool[msg.sender]);
        
        userUnlockingAmount[msg.sender] = amount;
        uint256 unlockTime = ((block.timestamp / 1 days) * 1 days) + 2 days + 1 minutes;
        userUnlockTime[msg.sender] = unlockTime;
        totalUnlocking += amount;
        
        emit UnlockInitiated(msg.sender, amount, unlockTime);
    }
    
    function completeUnlock() external nonReentrant {
        uint256 unlockTime = userUnlockTime[msg.sender];
        if (unlockTime == 0) revert NotUnlocking();
        if (block.timestamp < unlockTime) revert StillCoolingDown();
        
        _ensureIndexUpdated();
        
        uint256 amount = userUnlockingAmount[msg.sender];
        address vePool = userVotedPool[msg.sender];
        
        _checkpointUser(msg.sender);
        _syncPoolBaseline(vePool);
        
        poolVotes[vePool] -= amount;
        totalLockedVotes -= amount;
        totalUnlocking -= amount;
        
        userLockedAmount[msg.sender] -= amount;
        userUnlockingAmount[msg.sender] = 0;
        userUnlockTime[msg.sender] = 0;
        
        if (userLockedAmount[msg.sender] == 0) {
            userVotedPool[msg.sender] = address(0);
            _setUserBaselines(msg.sender, 0, 0);
        }
        
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
        
        // User gets (1-S) portion of incentives
        if (_baseIndex > metaBase) {
            uint256 deltaIndex = uint256(_baseIndex) - uint256(metaBase);
            uint256 S = getCurrentS();
            uint256 oneMinusS = PRECISION - S;
            uint256 incentivesDelta = (deltaIndex * INCENTIVES_BPS) / BPS;
            uint256 stakerPortion = (incentivesDelta * oneMinusS) / PRECISION;
            uint256 userShare = (stakerPortion * locked) / _totalLocked;
            userAccrued[user] += (TOTAL_SUPPLY * userShare) / PRECISION;
        }
        
        if (_feeIndex > feeBase) {
            uint256 feeDelta = uint256(_feeIndex) - uint256(feeBase);
            userFeeAccrued[user] += (feeDelta * locked) / PRECISION;
        }
        
        _setUserBaselines(user, _baseIndex, _feeIndex);
    }
    
    /**
     * @notice Sync pool baseline to current index
     * @dev Only syncs baseline - incentive distribution happens in updateIndex
     *      This prevents double-counting and keeps distribution centralized
     */
    function _syncPoolBaseline(address vePool) internal {
        if (!isWhitelistedVEPool[vePool]) return;
        if (vePoolChainId[vePool] != LOCAL_CHAIN_ID) return;  // Only local pools
        
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        uint128 _baseIndex = baseIndex;
        
        if (_baseIndex > poolBase) {
            _setPoolData(vePool, _baseIndex, poolAcc);
        }
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // CLAIMS (CEI COMPLIANT)
    // ════════════════════════════════════════════════════════════════════════
    
    function claimRewards() external nonReentrant returns (uint256 metaAmt, uint256 aeroAmt) {
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        
        metaAmt = userAccrued[msg.sender];
        aeroAmt = userFeeAccrued[msg.sender];
        
        if (metaAmt > 0) {
            uint256 avail = balanceOf(address(this));
            if (metaAmt > avail) metaAmt = avail;
            userAccrued[msg.sender] = 0;
        }
        
        if (aeroAmt > 0) {
            uint256 aeroAvail = AERO.balanceOf(address(this)) - _totalPoolFeeAccrued();
            if (aeroAmt > aeroAvail) aeroAmt = aeroAvail;
            userFeeAccrued[msg.sender] = 0;
        }
        
        if (metaAmt > 0) {
            _transfer(address(this), msg.sender, metaAmt);
        }
        if (aeroAmt > 0) {
            AERO.safeTransfer(msg.sender, aeroAmt);
        }
        
        emit RewardsClaimed(msg.sender, metaAmt, aeroAmt);
    }
    
    function claimStakerRewards() external nonReentrant returns (uint256 amount) {
        _ensureIndexUpdated();
        _checkpointUser(msg.sender);
        
        amount = userAccrued[msg.sender];
        if (amount == 0 || amount < MIN_CLAIM) revert NothingToClaim();
        
        uint256 avail = balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        userAccrued[msg.sender] = 0;
        
        uint256 aeroAmt = userFeeAccrued[msg.sender];
        if (aeroAmt > 0) {
            uint256 aeroAvail = AERO.balanceOf(address(this)) - _totalPoolFeeAccrued();
            if (aeroAmt > aeroAvail) aeroAmt = aeroAvail;
            userFeeAccrued[msg.sender] = 0;
        }
        
        _transfer(address(this), msg.sender, amount);
        if (aeroAmt > 0) {
            AERO.safeTransfer(msg.sender, aeroAmt);
        }
        
        emit RewardsClaimed(msg.sender, amount, aeroAmt);
    }
    
    /**
     * @notice VE pool claims its META allocation (S/2 portion of emissions)
     * @dev For local pools only. Remote pools claim from feeContract.
     */
    function claimForVEPool() external nonReentrant returns (uint256 amount) {
        address vePool = msg.sender;
        
        if (!isWhitelistedVEPool[vePool]) revert OnlyPool();
        if (vePoolChainId[vePool] != LOCAL_CHAIN_ID) revert NotLocalPool();
        
        _ensureIndexUpdated();
        _syncPoolBaseline(vePool);
        
        (uint128 poolBase, uint128 poolAcc) = _getPoolData(vePool);
        amount = uint256(poolAcc);
        if (amount == 0) return 0;
        
        uint256 avail = balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        _setPoolData(vePool, poolBase, 0);
        _transfer(address(this), vePool, amount);
        
        emit VEPoolClaimed(vePool, amount);
    }
    
    /**
     * @notice VE pool claims its AERO fee allocation
     * @dev Only for local (Base) pools. Remote pools get native fees locally.
     */
    function claimFeesForVEPool() external nonReentrant returns (uint256 amount) {
        address vePool = msg.sender;
        
        if (!isWhitelistedVEPool[vePool]) revert OnlyPool();
        if (vePoolChainId[vePool] != LOCAL_CHAIN_ID) revert NotLocalPool();
        
        amount = poolFeeAccrued[vePool];
        if (amount == 0) return 0;
        
        uint256 avail = AERO.balanceOf(address(this));
        if (amount > avail) amount = avail;
        
        poolFeeAccrued[vePool] = 0;
        AERO.safeTransfer(vePool, amount);
        
        emit VEPoolFeesClaimed(vePool, amount);
    }
    
    function claimTreasury() external nonReentrant returns (uint256 amount) {
        _ensureIndexUpdated();
        
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
        
        treasuryAccrued = 0;
        _transfer(address(this), TREASURY, amount);
        
        emit TreasuryClaimed(TREASURY, amount);
    }
    
    // ════════════════════════════════════════════════════════════════════════
    // VE POOL MANAGEMENT
    // ════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Add a VE pool on a specific chain
     * @param vePool The C-token address (C-AERO, C-VELO, etc.)
     * @param chainId Chain where the VE system lives
     * @param lpGauge_ LP gauge address (only meaningful for local pools)
     */
    function addVEPool(address vePool, uint256 chainId, address lpGauge_) external onlyMSIG {
        if (vePool == address(0)) revert ZeroAddress();
        if (isWhitelistedVEPool[vePool]) revert AlreadyWhitelisted();
        if (chainId != LOCAL_CHAIN_ID && !isWhitelistedChain[chainId]) revert ChainNotWhitelisted();
        
        isWhitelistedVEPool[vePool] = true;
        vePoolList.push(vePool);
        vePoolChainId[vePool] = chainId;
        poolLPGauge[vePool] = lpGauge_;
        _setPoolData(vePool, baseIndex, 0);
        
        emit VEPoolAdded(vePool, chainId, lpGauge_);
    }
    
    /**
     * @notice Add a local (Base) VE pool
     */
    function addVEPool(address vePool, address lpGauge_) external onlyMSIG {
        if (vePool == address(0)) revert ZeroAddress();
        if (isWhitelistedVEPool[vePool]) revert AlreadyWhitelisted();
        
        isWhitelistedVEPool[vePool] = true;
        vePoolList.push(vePool);
        vePoolChainId[vePool] = LOCAL_CHAIN_ID;
        poolLPGauge[vePool] = lpGauge_;
        _setPoolData(vePool, baseIndex, 0);
        
        emit VEPoolAdded(vePool, LOCAL_CHAIN_ID, lpGauge_);
    }
    
    function removeVEPool(address vePool) external onlyMSIG {
        if (!isWhitelistedVEPool[vePool]) revert NotWhitelisted();
        if (poolVotes[vePool] > 0) revert PoolHasActiveVotes();
        
        // Push any remaining LP rewards for local pools
        if (vePoolChainId[vePool] == LOCAL_CHAIN_ID) {
            _pushToLPGauge(vePool);
        }
        
        isWhitelistedVEPool[vePool] = false;
        poolLPGauge[vePool] = address(0);
        
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
    
    function _totalPoolFeeAccrued() internal view returns (uint256 total) {
        uint256 len = vePoolList.length;
        for (uint256 i = 0; i < len; ) {
            total += poolFeeAccrued[vePoolList[i]];
            unchecked { ++i; }
        }
    }
    
    function getVEPools() external view returns (address[] memory) {
        return vePoolList;
    }
    
    function getChainList() external view returns (uint256[] memory) {
        return chainList;
    }
    
    function isRemotePool(address vePool) external view returns (bool) {
        return isWhitelistedVEPool[vePool] && vePoolChainId[vePool] != LOCAL_CHAIN_ID;
    }
    
    function isLocalPool(address vePool) external view returns (bool) {
        return isWhitelistedVEPool[vePool] && vePoolChainId[vePool] == LOCAL_CHAIN_ID;
    }
    
    function getUserInfo(address user) external view returns (
        uint256 lockedAmount,
        uint256 unlockingAmount,
        address votedPool,
        uint256 unlockTime,
        uint256 pendingMeta,
        uint256 pendingAero
    ) {
        lockedAmount = userLockedAmount[user];
        unlockingAmount = userUnlockingAmount[user];
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
    
    function getAvailableToUnlock(address user) external view returns (uint256 available) {
        uint256 locked = userLockedAmount[user];
        uint256 unlocking = userUnlockingAmount[user];
        available = locked > unlocking ? locked - unlocking : 0;
    }
    
    function getPoolInfo(address vePool) external view returns (
        bool whitelisted,
        uint256 votes,
        uint256 pendingRewards,
        uint256 chainId,
        address lpGauge_,
        uint256 pendingLPMeta,
        uint256 pendingFees
    ) {
        whitelisted = isWhitelistedVEPool[vePool];
        votes = poolVotes[vePool];
        chainId = vePoolChainId[vePool];
        lpGauge_ = poolLPGauge[vePool];
        pendingLPMeta = poolLPAccruedMeta[vePool];
        pendingFees = poolFeeAccrued[vePool];
        
        (, uint128 poolAcc) = _getPoolData(vePool);
        pendingRewards = uint256(poolAcc);
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
    
    function getLPGaugeInfo(address vePool) external view returns (
        address gauge,
        uint256 pendingMeta
    ) {
        return (poolLPGauge[vePool], poolLPAccruedMeta[vePool]);
    }
    
    function getCrossChainStatus() external view returns (
        bool proofVerifierSet,
        uint256 whitelistedChainCount,
        uint256 localPoolCount,
        uint256 remotePoolCount
    ) {
        proofVerifierSet = l1ProofVerifier != address(0);
        whitelistedChainCount = chainList.length;
        
        uint256 len = vePoolList.length;
        for (uint256 i = 0; i < len; ) {
            if (vePoolChainId[vePoolList[i]] == LOCAL_CHAIN_ID) {
                localPoolCount++;
            } else {
                remotePoolCount++;
            }
            unchecked { ++i; }
        }
    }
    
    function getMultiVEStatus() external view returns (
        bool enabled,
        address feeContract_
    ) {
        enabled = multiVEEnabled;
        feeContract_ = feeContract;
    }
    
    // Legacy view functions
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

