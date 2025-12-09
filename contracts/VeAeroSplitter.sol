// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./DynamicGaugeVoteStorage.sol";
import "./DynamicPoolRegistry.sol";
import "./Interfaces.sol";

/**
 * @title VeAeroSplitter V3.2
 * @notice Wraps veAERO NFTs into fungible V-AERO and C-AERO tokens
 */

contract VeAeroSplitter is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;
    using DynamicGaugeVoteStorage for DynamicGaugeVoteStorage.PackedWeights;
    using DynamicPoolRegistry for DynamicPoolRegistry.Registry;
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public constant TREASURY_FEE_BPS = 100;    // 1% to treasury
    uint256 public constant META_FEE_BPS = 900;        // 9% to meta
    uint256 public constant MIN_DEPOSIT_AMOUNT = 1e18; // 1 AERO
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_VOTE_POOLS = 30;       // Aerodrome limit
    uint256 public constant POOL_BUFFER = 100;         // Extra slots for growth
    uint256 public constant MAX_CONSOLIDATE_PER_TX = 50; // Batch limit for NFT consolidation
    
    // Liquidation thresholds
    uint256 public constant C_LOCK_THRESHOLD_BPS = 2500;   // 25%
    uint256 public constant C_VOTE_THRESHOLD_BPS = 7500;   // 75%
    uint256 public constant V_CONFIRM_THRESHOLD_BPS = 5000; // 50%
    uint256 public constant C_VOTE_DURATION = 90 days;
    uint256 public constant R_CLAIM_WINDOW = 7 days;
    
    // ═══════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════
    
    IVotingEscrow public immutable VOTING_ESCROW;
    IERC20 public immutable AERO_TOKEN;
    IERC20 public immutable META_TOKEN;
    IVToken public immutable V_TOKEN;
    ICToken public immutable C_TOKEN;
    IRToken public immutable R_TOKEN;
    address public immutable TREASURY;
    address public immutable LIQUIDATION_MULTISIG;
    
    // ═══════════════════════════════════════════════════════════════
    // EXTERNAL CONTRACTS (Mutable)
    // ═══════════════════════════════════════════════════════════════
    
    IVoter public aerodromeVoter;
    IEpochGovernor public epochGovernor;
    
    // ═══════════════════════════════════════════════════════════════
    // DYNAMIC STORAGE CONFIG
    // ═══════════════════════════════════════════════════════════════
    
    DynamicGaugeVoteStorage.Config public storageConfig;
    DynamicPoolRegistry.Registry internal poolRegistry;
    DynamicGaugeVoteStorage.PackedWeights internal currentWeights;
    uint256 public weightsEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // NFT STATE
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public masterNftId;
    uint256[] public pendingNftIds;
    uint256 public pendingNftBlock;
    
    // ═══════════════════════════════════════════════════════════════
    // EPOCH STATE
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public currentEpoch;
    uint256 public epochEndTime;
    uint256 public votingStartTime;
    uint256 public votingEndTime;
    bool public voteExecutedThisEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // EMISSIONS VOTING
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public emissionsDecreaseTotal;
    uint256 public emissionsHoldTotal;
    uint256 public emissionsIncreaseTotal;
    
    // ═══════════════════════════════════════════════════════════════
    // V3: LIQUID FEE CLAIMS (replaces rebase)
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public globalFeeIndex;
    mapping(address => uint256) public userFeeCheckpoint;
    
    // ═══════════════════════════════════════════════════════════════
    // V3: META REWARD DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Global META reward index (rewards per C-AERO)
    uint256 public globalMetaIndex;
    
    /// @notice User's last claimed META index
    mapping(address => uint256) public userMetaCheckpoint;
    
    /// @notice Total META already indexed for distribution
    uint256 public totalMetaIndexed;
    
    // ═══════════════════════════════════════════════════════════════
    // V3: BRIBE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Total V-AERO locked for voting this epoch (for bribe pro-rata)
    uint256 public totalVLockedForVoting;
    
    /// @notice Total passive votes this epoch (follows active vote proportions)
    uint256 public totalPassiveVotes;
    
    /// @notice User's snapshotted vote power for bribe claims
    mapping(address => uint256) public snapshotVotePower;
    
    /// @notice Epoch user snapshotted in
    mapping(address => uint256) public snapshotEpoch;
    
    /// @notice Total snapshot power (set by first snapshot each epoch)
    uint256 public epochSnapshotTotal;
    
    /// @notice Epoch the snapshot total is for
    uint256 public epochSnapshotEpoch;
    
    /// @notice Bribe ratio per V-AERO for each token (set by first claimer)
    mapping(address => uint256) public bribeRatioPerV;
    
    /// @notice Epoch the bribe ratio was set in
    mapping(address => uint256) public bribeTokenEpoch;
    
    /// @notice Epoch user claimed bribes in
    mapping(address => uint256) public claimedBribesEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // LIQUIDATION STATE
    // ═══════════════════════════════════════════════════════════════
    
    enum LiquidationPhase { Normal, CLock, CVote, VConfirm, Approved, Closed }
    
    LiquidationPhase public liquidationPhase;
    uint256 public totalCLocked;
    uint256 public totalVLocked;
    uint256 public cVoteStartTime;          // V3: renamed from cLockStartTime
    uint256 public vConfirmEpoch;           // V3: epoch-based instead of time
    uint256 public liquidationApprovedTime;
    uint256 public cSupplyAtLiquidation;
    uint256 public totalRClaimed;
    
    mapping(address => uint256) public cLockedForLiquidation;
    mapping(address => uint256) public vLockedForLiquidation;
    mapping(address => bool) public hasClaimedR;
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    // Config events
    event StorageConfigured(uint256 maxPools, uint256 bitsPerPool, uint256 poolsPerSlot, uint256 numSlots, uint256 maxWeightPerPool);
    event StorageExpanded(uint256 oldMaxPools, uint256 newMaxPools);
    
    // Deposit events
    event NFTDeposited(address indexed user, uint256 indexed tokenId, uint256 lockedAmount, uint256 userAmount, uint256 treasuryAmount, uint256 metaAmount);
    event MasterNftSet(uint256 indexed tokenId);
    event NFTConsolidated(uint256 indexed sourceId, uint256 indexed masterId);
    event PendingNftAdded(uint256 indexed tokenId, uint256 batchSize);
    event BatchConsolidated(uint256 count, uint256 indexed masterNftId);
    
    // Voting events
    event GaugeVoteRecorded(address indexed user, uint256 indexed epoch, address indexed pool, uint256 amount);
    event PassiveVoteRecorded(address indexed user, uint256 indexed epoch, uint256 amount);
    event EmissionsVoteRecorded(address indexed user, uint256 indexed epoch, int8 choice, uint256 amount);
    event GaugeVoteExecuted(address[] pools, uint256[] weights, uint256 activeTotal, uint256 passiveTotal);
    event EmissionsVoteExecuted(uint256 proposalId, uint8 support, uint256 totalVotes);
    event PoolRegistered(address indexed pool, uint256 indexed index);
    
    // Epoch events
    event EpochReset(uint256 indexed newEpoch, uint256 newEndTime);
    event VotingWindowSet(uint256 indexed epoch, uint256 votingStart, uint256 votingEnd, uint256 epochEnd);
    
    // V3: Fee claim events (replaces rebase)
    event FeesCollected(uint256 totalAero, uint256 holderShare, uint256 metaShare, uint256 newFeeIndex);
    event FeesClaimed(address indexed user, uint256 amount);
    
    // V3: META reward events
    event MetaCollected(uint256 amount, uint256 newMetaIndex);
    event MetaClaimed(address indexed user, uint256 amount);
    
    // V3: Bribe events
    event BribeSnapshot(address indexed user, uint256 votePower, uint256 epoch);
    event EpochSnapshotSet(uint256 totalPower, uint256 epoch);
    event BribesClaimed(address indexed user, address[] tokens, uint256[] amounts);
    event BribeTokenRegistered(address indexed token, uint256 ratio, uint256 epoch);
    event UnclaimedBribesSwept(address indexed token, uint256 amount);
    
    // V3.1: Transfer settlement events
    event FeesSweptToTreasury(address indexed from, uint256 amount);
    event MetaSweptToTreasury(address indexed from, uint256 amount);
    
    // Liquidation events
    event LiquidationPhaseChanged(LiquidationPhase oldPhase, LiquidationPhase newPhase);
    event CLocked(address indexed user, uint256 amount);
    event VLocked(address indexed user, uint256 amount);
    event RTokensClaimed(address indexed user, uint256 amount);
    event UnclaimedReceiptsSwept(uint256 amount);
    event NFTsWithdrawn(address indexed to, uint256 tokenId);
    event FailedLiquidationWithdrawn(address indexed user, uint256 cAmount, uint256 vAmount);
    
    // Admin events
    event AerodromeVoterUpdated(address indexed newVoter);
    event EpochGovernorUpdated(address indexed newGovernor);
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error ZeroAddress();
    error ZeroAmount();
    error NotNFTOwner();
    error NFTAlreadyVoted();
    error OnlyPermanentLocksAccepted();
    error AmountTooSmall();
    error NoMasterNft();
    error NoPendingNfts();
    error PendingNotReady();
    error DepositsDisabled();
    error VoteAlreadyExecuted();
    error NoVotesToExecute();
    error VotingNotStarted();
    error VotingEnded();
    error ExecutionWindowClosed();
    error NotNewEpoch();
    error CantSweepAero();
    error NothingToClaim();
    error NothingToWithdraw();
    error InvalidLiquidationPhase();
    error ThresholdNotReached();
    error WindowExpired();
    error OnlyMultisig();
    error OnlyVToken();
    error OnlyCToken();
    error InvalidGauge(address pool);
    error GaugeNotAlive(address pool);
    error StorageNotConfigured();
    error ExceedsAbsoluteMax(uint256 requested, uint256 absoluteMax);
    error SnapshotWindowClosed();
    error AlreadySnapshotted();
    error NoLockedBalance();
    error NoSnapshotLastEpoch();
    error AlreadyClaimedBribes();
    error CVoteNotExpired();
    error VConfirmEpochNotEnded();
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor(
        address _votingEscrow,
        address _aeroToken,
        address _metaToken,
        address _vToken,
        address _cToken,
        address _rToken,
        address _treasury,
        address _liquidationMultisig,
        address _aerodromeVoter,
        address _epochGovernor
    ) Ownable(msg.sender) {
        if (_votingEscrow == address(0)) revert ZeroAddress();
        if (_aeroToken == address(0)) revert ZeroAddress();
        if (_metaToken == address(0)) revert ZeroAddress();
        if (_vToken == address(0)) revert ZeroAddress();
        if (_cToken == address(0)) revert ZeroAddress();
        if (_rToken == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_liquidationMultisig == address(0)) revert ZeroAddress();
        if (_aerodromeVoter == address(0)) revert ZeroAddress();
        if (_epochGovernor == address(0)) revert ZeroAddress();
        
        VOTING_ESCROW = IVotingEscrow(_votingEscrow);
        AERO_TOKEN = IERC20(_aeroToken);
        META_TOKEN = IERC20(_metaToken);
        V_TOKEN = IVToken(_vToken);
        C_TOKEN = ICToken(_cToken);
        R_TOKEN = IRToken(_rToken);
        TREASURY = _treasury;
        LIQUIDATION_MULTISIG = _liquidationMultisig;
        aerodromeVoter = IVoter(_aerodromeVoter);
        epochGovernor = IEpochGovernor(_epochGovernor);
        
        // Initialize epoch
        currentEpoch = 1;
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        globalFeeIndex = PRECISION;
        globalMetaIndex = PRECISION;
        weightsEpoch = 1;
        
        _configureStorage();
        
        emit EpochReset(1, epochEndTime);
        emit VotingWindowSet(1, votingStartTime, votingEndTime, epochEndTime);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // EPOCH RESET
    // ═══════════════════════════════════════════════════════════════
    
    modifier ensureCurrentEpoch() {
        if (block.timestamp >= epochEndTime) {
            _resetEpoch();
        }
        _;
    }
    
    function resetEpoch() external {
        if (block.timestamp < epochEndTime) revert NotNewEpoch();
        _resetEpoch();
    }
    
    function _resetEpoch() internal {
        currentEpoch++;
        
        // Reset vote totals
        emissionsDecreaseTotal = 0;
        emissionsHoldTotal = 0;
        emissionsIncreaseTotal = 0;
        voteExecutedThisEpoch = false;
        totalVLockedForVoting = 0;
        totalPassiveVotes = 0;
        
        // Calculate new timing
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        
        _checkAndExpandStorage();
        
        if (storageConfig.maxPools > 0) {
            currentWeights.clearAll();
            poolRegistry.clear();
            weightsEpoch = currentEpoch;
        }
        
        emit EpochReset(currentEpoch, epochEndTime);
        emit VotingWindowSet(currentEpoch, votingStartTime, votingEndTime, epochEndTime);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // STORAGE CONFIGURATION
    // ═══════════════════════════════════════════════════════════════
    
    function _configureStorage() internal {
        uint256 poolCount = 300;
        uint256 totalSupply = AERO_TOKEN.totalSupply();
        
        storageConfig = DynamicGaugeVoteStorage.calculateConfig(
            totalSupply,
            poolCount,
            POOL_BUFFER,
            DynamicGaugeVoteStorage.ABSOLUTE_MAX_SLOTS
        );
        
        currentWeights.initialize(storageConfig);
        poolRegistry.initialize(storageConfig.maxPools);
        
        emit StorageConfigured(
            storageConfig.maxPools,
            storageConfig.bitsPerPool,
            storageConfig.poolsPerSlot,
            storageConfig.numSlots,
            storageConfig.maxWeight
        );
    }
    
    function _checkAndExpandStorage() internal {
        uint256 registeredPools = poolRegistry.nextIndex;
        uint256 totalSupply = AERO_TOKEN.totalSupply();
        
        bool needsMorePools = (registeredPools + POOL_BUFFER > storageConfig.maxPools);
        
        // Calculate bits needed, clamped to the same max that calculateConfig uses (64)
        uint256 bitsNeeded = DynamicGaugeVoteStorage.log2Ceil(totalSupply) + 1;
        if (bitsNeeded > 64) bitsNeeded = 64; // MAX_BITS_PER_POOL
        bool needsMoreBits = (bitsNeeded > storageConfig.bitsPerPool);
        
        if (!needsMorePools && !needsMoreBits) return;
        
        uint256 oldMaxPools = storageConfig.maxPools;
        
        // Note: storageConfig.maxPools already includes POOL_BUFFER from initial config
        // We need to work with the base pool count to avoid double-buffering
        uint256 basePoolCount = storageConfig.maxPools > POOL_BUFFER 
            ? storageConfig.maxPools - POOL_BUFFER 
            : 0;
        
        uint256 newPoolCount = registeredPools > basePoolCount / 2 
            ? basePoolCount * 2 
            : basePoolCount;
        
        storageConfig = DynamicGaugeVoteStorage.calculateConfig(
            totalSupply,
            newPoolCount,
            POOL_BUFFER,
            DynamicGaugeVoteStorage.ABSOLUTE_MAX_SLOTS
        );
        
        currentWeights.initialize(storageConfig);
        poolRegistry.setMaxPools(storageConfig.maxPools);
        
        emit StorageExpanded(oldMaxPools, storageConfig.maxPools);
        emit StorageConfigured(
            storageConfig.maxPools,
            storageConfig.bitsPerPool,
            storageConfig.poolsPerSlot,
            storageConfig.numSlots,
            storageConfig.maxWeight
        );
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ERC721 RECEIVER
    // ═══════════════════════════════════════════════════════════════
    
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // DEPOSIT FUNCTIONS (V3: 18 decimals, 9% to Meta)
    // ═══════════════════════════════════════════════════════════════
    
    function depositVeAero(uint256 tokenId) external nonReentrant ensureCurrentEpoch {
        if (!_isDepositWindowOpen()) revert DepositsDisabled();
        
        if (pendingNftIds.length > 0 && block.number > pendingNftBlock) {
            _consolidateAll();
        }
        
        if (VOTING_ESCROW.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
        if (VOTING_ESCROW.voted(tokenId)) revert NFTAlreadyVoted();
        
        IVotingEscrow.LockedBalance memory locked = VOTING_ESCROW.locked(tokenId);
        if (!locked.isPermanent) revert OnlyPermanentLocksAccepted();
        if (uint256(uint128(locked.amount)) < MIN_DEPOSIT_AMOUNT) revert AmountTooSmall();
        
        uint256 lockedAmount = uint256(uint128(locked.amount));
        
        // V3: Calculate splits (18 decimals)
        // Treasury: 1%, Meta: 9% (V only), User: 90% V, 99% C
        uint256 treasuryAmount = (lockedAmount * TREASURY_FEE_BPS) / 10000;
        uint256 metaAmount = (lockedAmount * META_FEE_BPS) / 10000;
        uint256 userVAmount = lockedAmount - treasuryAmount - metaAmount;  // 90%
        uint256 userCAmount = lockedAmount - treasuryAmount;               // 99%
        
        // Set fee checkpoint for new depositor
        if (userFeeCheckpoint[msg.sender] == 0) {
            userFeeCheckpoint[msg.sender] = globalFeeIndex;
        }
        
        // V3.1: Set META checkpoint for new depositor
        if (userMetaCheckpoint[msg.sender] == 0) {
            userMetaCheckpoint[msg.sender] = globalMetaIndex;
        }
        
        VOTING_ESCROW.safeTransferFrom(msg.sender, address(this), tokenId);
        
        bool isFirstDeposit = (masterNftId == 0);
        
        if (isFirstDeposit) {
            masterNftId = tokenId;
            emit MasterNftSet(tokenId);
        } else {
            pendingNftIds.push(tokenId);
            pendingNftBlock = block.number;
            emit PendingNftAdded(tokenId, pendingNftIds.length);
        }
        
        // V3.2: Mint tokens (18 decimals)
        // Treasury: 1%, META contract: 9%, User: 90%
        V_TOKEN.mint(msg.sender, userVAmount);
        V_TOKEN.mint(TREASURY, treasuryAmount);           // 1% to treasury
        V_TOKEN.mint(address(META_TOKEN), metaAmount);    // 9% to META contract
        
        C_TOKEN.mint(msg.sender, userCAmount);
        C_TOKEN.mint(TREASURY, treasuryAmount);
        
        emit NFTDeposited(msg.sender, tokenId, lockedAmount, userVAmount, treasuryAmount, metaAmount);
    }
    
    function consolidate() external nonReentrant {
        if (pendingNftIds.length == 0) revert NoPendingNfts();
        if (block.number <= pendingNftBlock) revert PendingNotReady();
        _consolidateAll();
    }
    
    function _consolidateAll() internal {
        uint256 totalCount = pendingNftIds.length;
        if (totalCount == 0) return;
        
        uint256 master = masterNftId;
        
        // Batch limit: process up to MAX_CONSOLIDATE_PER_TX at a time
        uint256 processCount = totalCount > MAX_CONSOLIDATE_PER_TX ? MAX_CONSOLIDATE_PER_TX : totalCount;
        
        // Copy items to process
        uint256[] memory toProcess = new uint256[](processCount);
        for (uint256 i = 0; i < processCount; i++) {
            toProcess[i] = pendingNftIds[i];
        }
        
        // Remove processed items from array (shift remaining left)
        if (processCount == totalCount) {
            // All processed - clear everything
            delete pendingNftIds;
            pendingNftBlock = 0;
        } else {
            // Partial processing - shift array
            uint256 remaining = totalCount - processCount;
            for (uint256 i = 0; i < remaining; i++) {
                pendingNftIds[i] = pendingNftIds[i + processCount];
            }
            // Pop the extra elements
            for (uint256 i = 0; i < processCount; i++) {
                pendingNftIds.pop();
            }
            // Keep pendingNftBlock since there are still pending NFTs
        }
        
        // Process the batch
        for (uint256 i = 0; i < processCount; i++) {
            uint256 pending = toProcess[i];
            VOTING_ESCROW.unlockPermanent(pending);
            VOTING_ESCROW.merge(pending, master);
            emit NFTConsolidated(pending, master);
        }
        
        emit BatchConsolidated(processCount, master);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // GAUGE VOTING
    // ═══════════════════════════════════════════════════════════════
    
    function recordGaugeVote(
        address user,
        address pool,
        uint256 amount  // V3: Already in whole tokens from VToken
    ) external ensureCurrentEpoch {
        if (msg.sender != address(V_TOKEN)) revert OnlyVToken();
        if (storageConfig.maxPools == 0) revert StorageNotConfigured();
        
        address gauge = aerodromeVoter.gauges(pool);
        if (!aerodromeVoter.isGauge(gauge)) revert InvalidGauge(pool);
        if (!aerodromeVoter.isAlive(gauge)) revert GaugeNotAlive(pool);
        
        if (weightsEpoch != currentEpoch) {
            currentWeights.clearAll();
            poolRegistry.clear();
            weightsEpoch = currentEpoch;
        }
        
        (uint256 poolIndex, bool isNew) = poolRegistry.getOrRegister(pool);
        
        if (isNew) {
            emit PoolRegistered(pool, poolIndex);
        }
        
        currentWeights.addWeight(storageConfig, poolIndex, amount);
        
        // V3: Track total V locked for bribe distribution
        // Note: VToken stores locked in 18 decimals, amount here is whole tokens
        totalVLockedForVoting += amount;
        
        emit GaugeVoteRecorded(user, currentEpoch, pool, amount);
    }
    
    /**
     * @notice Record a passive vote that follows active vote proportions
     * @dev Passive votes are distributed proportionally to active votes at execution
     * @param user The voter
     * @param amount Vote weight in whole tokens
     */
    function recordPassiveVote(
        address user,
        uint256 amount
    ) external ensureCurrentEpoch {
        if (msg.sender != address(V_TOKEN)) revert OnlyVToken();
        if (amount == 0) revert ZeroAmount();
        
        totalPassiveVotes += amount;
        
        // Passive votes still count for bribe eligibility
        totalVLockedForVoting += amount;
        
        emit PassiveVoteRecorded(user, currentEpoch, amount);
    }
    
    function executeGaugeVote() external nonReentrant {
        if (masterNftId == 0) revert NoMasterNft();
        if (voteExecutedThisEpoch) revert VoteAlreadyExecuted();
        if (storageConfig.maxPools == 0) revert StorageNotConfigured();
        
        if (block.timestamp < votingEndTime) revert ExecutionWindowClosed();
        if (block.timestamp > votingEndTime + 1 hours) revert ExecutionWindowClosed();
        
        if (pendingNftIds.length > 0 && block.number > pendingNftBlock) {
            _consolidateAll();
        }
        
        (
            address[] memory pools,
            uint256[] memory weights,
            uint256 count
        ) = currentWeights.findTopPools(
            storageConfig,
            poolRegistry.indexToPool,
            MAX_VOTE_POOLS
        );
        
        // Must have at least one active vote (passive votes need something to follow)
        if (count == 0) revert NoVotesToExecute();
        
        // Calculate total active weight
        uint256 totalActiveWeight = 0;
        for (uint256 i = 0; i < count; i++) {
            totalActiveWeight += weights[i];
        }
        
        address[] memory finalPools = new address[](count);
        uint256[] memory finalWeights = new uint256[](count);
        
        // Distribute passive votes proportionally to active votes
        // Formula: finalWeight = activeWeight * (totalActive + totalPassive) / totalActive
        // This preserves proportions while scaling up by passive votes
        uint256 passive = totalPassiveVotes;
        
        for (uint256 i = 0; i < count; i++) {
            finalPools[i] = pools[i];
            if (passive > 0 && totalActiveWeight > 0) {
                // Scale up: each pool gets its proportion of passive votes added
                finalWeights[i] = (weights[i] * (totalActiveWeight + passive)) / totalActiveWeight;
            } else {
                finalWeights[i] = weights[i];
            }
        }
        
        voteExecutedThisEpoch = true;
        
        aerodromeVoter.vote(masterNftId, finalPools, finalWeights);
        
        emit GaugeVoteExecuted(finalPools, finalWeights, totalActiveWeight, passive);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // EMISSIONS VOTING
    // ═══════════════════════════════════════════════════════════════
    
    function recordEmissionsVote(
        address user,
        int8 choice,
        uint256 amount  // V3: Already in whole tokens from CToken
    ) external ensureCurrentEpoch {
        if (msg.sender != address(C_TOKEN)) revert OnlyCToken();
        
        if (choice == -1) {
            emissionsDecreaseTotal += amount;
        } else if (choice == 0) {
            emissionsHoldTotal += amount;
        } else {
            emissionsIncreaseTotal += amount;
        }
        
        emit EmissionsVoteRecorded(user, currentEpoch, choice, amount);
    }
    
    function executeEmissionsVote(uint256 proposalId) external nonReentrant {
        if (masterNftId == 0) revert NoMasterNft();
        if (block.timestamp < votingEndTime) revert ExecutionWindowClosed();
        if (block.timestamp > votingEndTime + 1 hours) revert ExecutionWindowClosed();
        
        uint256 maxVotes = emissionsHoldTotal;
        uint8 support = 2; 
        
        if (emissionsDecreaseTotal > maxVotes) {
            maxVotes = emissionsDecreaseTotal;
            support = 0;
        }
        if (emissionsIncreaseTotal > maxVotes) {
            maxVotes = emissionsIncreaseTotal;
            support = 1;
        }
        
        epochGovernor.castVote(proposalId, support);
        
        uint256 totalVotes = emissionsDecreaseTotal + emissionsHoldTotal + emissionsIncreaseTotal;
        emit EmissionsVoteExecuted(proposalId, support, totalVotes);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // V3.2: LIQUID FEE CLAIMS (50/50 split)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Collect trading fees from Aerodrome and update fee index
     * @dev V3.2: 50% to META contract, 50% to C-AERO holders
     */
    function collectFees(
        address[] calldata fees,
        address[][] calldata tokens
    ) external nonReentrant {
        if (masterNftId == 0) revert NoMasterNft();
        
        uint256 balanceBefore = AERO_TOKEN.balanceOf(address(this));
        aerodromeVoter.claimFees(fees, tokens, masterNftId);
        uint256 aeroReceived = AERO_TOKEN.balanceOf(address(this)) - balanceBefore;
        
        if (aeroReceived > 0) {
            // V3.2: Split fees 50/50 between META and C-AERO holders
            uint256 metaShare = aeroReceived >> 1;  // 50% to META
            uint256 holderShare = aeroReceived - metaShare;  // 50% to C-AERO
            
            // Send 50% to META contract for distribution
            AERO_TOKEN.approve(address(META_TOKEN), metaShare);
            IMeta(address(META_TOKEN)).receiveFees(metaShare);
            
            // Update fee index for C-AERO holders (50%)
            uint256 cSupply = C_TOKEN.totalSupply();
            if (cSupply > 0) {
                globalFeeIndex += (holderShare * PRECISION) / cSupply;
            }
            
            emit FeesCollected(aeroReceived, holderShare, metaShare, globalFeeIndex);
        }
    }
    
    /**
     * @notice Claim pending trading fees as liquid AERO
     * @dev V3.1: Handles first-time claimers to prevent windfall
     */
    function claimFees() external nonReentrant returns (uint256 owed) {
        uint256 balance = C_TOKEN.balanceOf(msg.sender);
        uint256 checkpoint = userFeeCheckpoint[msg.sender];
        
        // V3.1: First-time claimers (checkpoint == 0) get initialized, no windfall
        if (checkpoint == 0) {
            userFeeCheckpoint[msg.sender] = globalFeeIndex;
            revert NothingToClaim();
        }
        
        if (checkpoint >= globalFeeIndex) revert NothingToClaim();
        if (balance == 0) revert NothingToClaim();
        
        owed = (balance * (globalFeeIndex - checkpoint)) / PRECISION;
        
        userFeeCheckpoint[msg.sender] = globalFeeIndex;
        
        if (owed > 0) {
            AERO_TOKEN.safeTransfer(msg.sender, owed);
            emit FeesClaimed(msg.sender, owed);
        }
    }
    
    /**
     * @notice Get pending fee claim amount
     * @dev V3.1: Returns 0 for uninitialized users (checkpoint == 0)
     */
    function pendingFees(address user) external view returns (uint256) {
        uint256 balance = C_TOKEN.balanceOf(user);
        uint256 checkpoint = userFeeCheckpoint[user];
        
        // V3.1: Uninitialized users have no pending fees
        if (checkpoint == 0 || checkpoint >= globalFeeIndex || balance == 0) return 0;
        
        return (balance * (globalFeeIndex - checkpoint)) / PRECISION;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // V3: META REWARD CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Collect META rewards from Meta contract and update distribution index
     * @dev Called after Meta.mintEpochRewards() - anyone can call
     *      Updates globalMetaIndex based on new META since last collection
     */
    function collectMeta() external nonReentrant {
        uint256 metaBalance = META_TOKEN.balanceOf(address(this));
        uint256 cSupply = C_TOKEN.totalSupply();
        
        // Calculate new META since last collection
        uint256 newMeta = metaBalance - totalMetaIndexed;
        
        if (newMeta == 0) revert NothingToClaim();
        if (cSupply == 0) revert NothingToClaim();
        
        // Update tracking
        totalMetaIndexed = metaBalance;
        
        // Update index for new META only
        globalMetaIndex += (newMeta * PRECISION) / cSupply;
        
        emit MetaCollected(newMeta, globalMetaIndex);
    }
    
    /**
     * @notice Claim pending META rewards
     * @return owed Amount of META claimed
     */
    function claimMeta() external nonReentrant returns (uint256 owed) {
        uint256 balance = C_TOKEN.balanceOf(msg.sender);
        uint256 checkpoint = userMetaCheckpoint[msg.sender];
        
        // Initialize checkpoint for first-time claimers
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        
        if (checkpoint >= globalMetaIndex) revert NothingToClaim();
        if (balance == 0) revert NothingToClaim();
        
        owed = (balance * (globalMetaIndex - checkpoint)) / PRECISION;
        
        userMetaCheckpoint[msg.sender] = globalMetaIndex;
        
        if (owed > 0) {
            // Update tracking before transfer
            totalMetaIndexed -= owed;
            META_TOKEN.safeTransfer(msg.sender, owed);
            emit MetaClaimed(msg.sender, owed);
        }
    }
    
    /**
     * @notice Get pending META reward amount
     */
    function pendingMeta(address user) external view returns (uint256) {
        uint256 balance = C_TOKEN.balanceOf(user);
        uint256 checkpoint = userMetaCheckpoint[user];
        
        // Handle first-time claimers
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        
        if (checkpoint >= globalMetaIndex || balance == 0) return 0;
        
        return (balance * (globalMetaIndex - checkpoint)) / PRECISION;
    }
    
    /**
     * @notice Initialize META checkpoint for new C-AERO holder
     * @dev Call this when receiving C-AERO to avoid claiming past rewards
     */
    function initializeMetaCheckpoint() external {
        if (userMetaCheckpoint[msg.sender] == 0) {
            userMetaCheckpoint[msg.sender] = globalMetaIndex;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // V3.1: TRANSFER SETTLEMENT (NO WINDFALL)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Handle C-AERO transfer - settle sender, weight-average receiver checkpoint
     * @dev Called by CToken._update BEFORE balance modification
     *      CEI Pattern: All READS → All CALCULATIONS → All EFFECTS → All INTERACTIONS
     *      - Sender: unclaimed fees/META swept to treasury, checkpoint reset
     *      - Receiver: weighted average checkpoint so incoming tokens don't inherit history
     * @param from Sender address
     * @param to Receiver address  
     * @param amount Transfer amount
     */
    function onCTokenTransfer(address from, address to, uint256 amount) external {
        if (msg.sender != address(C_TOKEN)) revert OnlyCToken();
        
        // Skip mints and burns (CToken only calls for actual transfers)
        if (from == address(0) || to == address(0)) return;
        
        // ═══════════════════════════════════════════════════════════
        // READS: Get all balances and checkpoints BEFORE any state changes
        // ═══════════════════════════════════════════════════════════
        
        uint256 fromBalance = C_TOKEN.balanceOf(from);
        uint256 toBalance = C_TOKEN.balanceOf(to);
        
        uint256 fromFeeCheckpoint = userFeeCheckpoint[from];
        uint256 fromMetaCheckpoint = userMetaCheckpoint[from];
        if (fromMetaCheckpoint == 0) fromMetaCheckpoint = PRECISION;
        
        uint256 toFeeCheckpoint = userFeeCheckpoint[to];
        if (toFeeCheckpoint == 0) toFeeCheckpoint = globalFeeIndex;
        
        uint256 toMetaCheckpoint = userMetaCheckpoint[to];
        if (toMetaCheckpoint == 0) toMetaCheckpoint = globalMetaIndex;
        
        // ═══════════════════════════════════════════════════════════
        // CALCULATIONS: Compute all amounts before any state changes
        // ═══════════════════════════════════════════════════════════
        
        uint256 unclaimedFees = 0;
        if (fromFeeCheckpoint > 0 && fromFeeCheckpoint < globalFeeIndex && fromBalance > 0) {
            unclaimedFees = (fromBalance * (globalFeeIndex - fromFeeCheckpoint)) / PRECISION;
        }
        
        uint256 unclaimedMeta = 0;
        if (fromMetaCheckpoint < globalMetaIndex && fromBalance > 0) {
            unclaimedMeta = (fromBalance * (globalMetaIndex - fromMetaCheckpoint)) / PRECISION;
        }
        
        uint256 newTotal = toBalance + amount;
        uint256 newToFeeCheckpoint = toFeeCheckpoint;
        uint256 newToMetaCheckpoint = toMetaCheckpoint;
        
        if (newTotal > 0) {
            newToFeeCheckpoint = ((toBalance * toFeeCheckpoint) + (amount * globalFeeIndex)) / newTotal;
            newToMetaCheckpoint = ((toBalance * toMetaCheckpoint) + (amount * globalMetaIndex)) / newTotal;
        }
        
        // ═══════════════════════════════════════════════════════════
        // EFFECTS: Update ALL state BEFORE any external calls
        // ═══════════════════════════════════════════════════════════
        
        // Sender checkpoints reset to current
        userFeeCheckpoint[from] = globalFeeIndex;
        userMetaCheckpoint[from] = globalMetaIndex;
        
        // Receiver checkpoints set to weighted average
        userFeeCheckpoint[to] = newToFeeCheckpoint;
        userMetaCheckpoint[to] = newToMetaCheckpoint;
        
        // Update META tracking (effect, not interaction)
        if (unclaimedMeta > 0) {
            totalMetaIndexed -= unclaimedMeta;
        }
        
        // ═══════════════════════════════════════════════════════════
        // INTERACTIONS: All external transfers LAST
        // ═══════════════════════════════════════════════════════════
        
        if (unclaimedFees > 0) {
            AERO_TOKEN.safeTransfer(TREASURY, unclaimedFees);
            emit FeesSweptToTreasury(from, unclaimedFees);
        }
        
        if (unclaimedMeta > 0) {
            META_TOKEN.safeTransfer(TREASURY, unclaimedMeta);
            emit MetaSweptToTreasury(from, unclaimedMeta);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // V3: BRIBE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Collect bribes from Aerodrome (stays in contract for distribution)
     */
    function collectBribes(
        address[] calldata bribes,
        address[][] calldata tokens
    ) external nonReentrant {
        if (masterNftId == 0) revert NoMasterNft();
        aerodromeVoter.claimBribes(bribes, tokens, masterNftId);
    }
    
    /**
     * @notice Snapshot V-AERO locked balance for bribe eligibility
     * @dev Only callable in 1-hour window after voting ends (Wed 22:00 - Wed 23:00)
     */
    function snapshotForBribes() external {
        // Must be after voting ends but before epoch ends
        if (block.timestamp <= votingEndTime) revert SnapshotWindowClosed();
        if (block.timestamp >= epochEndTime) revert SnapshotWindowClosed();
        
        // Must have locked V-AERO
        uint256 locked = V_TOKEN.lockedAmount(msg.sender);
        if (locked == 0) revert NoLockedBalance();
        
        // Can only snapshot once per epoch
        if (snapshotEpoch[msg.sender] == currentEpoch) revert AlreadySnapshotted();
        
        // First snapshot sets the total
        if (epochSnapshotEpoch != currentEpoch) {
            epochSnapshotTotal = totalVLockedForVoting;
            epochSnapshotEpoch = currentEpoch;
            emit EpochSnapshotSet(epochSnapshotTotal, currentEpoch);
        }
        
        // Record user's snapshot (in whole tokens to match totalVLockedForVoting)
        uint256 lockedWholeTokens = locked / 1e18;
        snapshotVotePower[msg.sender] = lockedWholeTokens;
        snapshotEpoch[msg.sender] = currentEpoch;
        
        emit BribeSnapshot(msg.sender, lockedWholeTokens, currentEpoch);
    }
    
    /**
     * @notice Claim bribe tokens pro-rata to snapshot power
     * @param tokens Array of bribe token addresses to claim
     */
    function claimBribes(address[] calldata tokens) external nonReentrant {
        // Must have snapshotted in prior epoch
        if (snapshotEpoch[msg.sender] != currentEpoch - 1) revert NoSnapshotLastEpoch();
        
        // Can only claim once per epoch
        if (claimedBribesEpoch[msg.sender] == currentEpoch) revert AlreadyClaimedBribes();
        
        claimedBribesEpoch[msg.sender] = currentEpoch;
        
        uint256 userPower = snapshotVotePower[msg.sender];
        uint256 totalPower = epochSnapshotTotal;
        
        uint256[] memory amounts = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(AERO_TOKEN)) continue;  // AERO is for fee claims
            
            // First claimer registers ratio for this token
            if (bribeTokenEpoch[token] != currentEpoch) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance > 0 && totalPower > 0) {
                    bribeRatioPerV[token] = (balance * PRECISION) / totalPower;
                    bribeTokenEpoch[token] = currentEpoch;
                    emit BribeTokenRegistered(token, bribeRatioPerV[token], currentEpoch);
                }
            }
            
            uint256 owed = (userPower * bribeRatioPerV[token]) / PRECISION;
            amounts[i] = owed;
            
            if (owed > 0) {
                IERC20(token).safeTransfer(msg.sender, owed);
            }
        }
        
        emit BribesClaimed(msg.sender, tokens, amounts);
    }
    
    /**
     * @notice Sweep unclaimed bribes to treasury after epoch ends
     */
    function sweepUnclaimedBribes(address[] calldata tokens) external {
        if (block.timestamp < epochEndTime) revert WindowExpired();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(AERO_TOKEN)) continue;
            
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(TREASURY, balance);
                emit UnclaimedBribesSwept(token, balance);
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // LIQUIDATION (V3: Fixed 90-day CVote, 1 epoch VConfirm)
    // ═══════════════════════════════════════════════════════════════
    
    function recordCLock(address user, uint256 amount) external {
        if (msg.sender != address(C_TOKEN)) revert OnlyCToken();
        if (liquidationPhase != LiquidationPhase.Normal &&
            liquidationPhase != LiquidationPhase.CLock &&
            liquidationPhase != LiquidationPhase.CVote) {
            revert InvalidLiquidationPhase();
        }
        
        cLockedForLiquidation[user] += amount;
        totalCLocked += amount;
        
        if (liquidationPhase == LiquidationPhase.Normal) {
            liquidationPhase = LiquidationPhase.CLock;
            emit LiquidationPhaseChanged(LiquidationPhase.Normal, LiquidationPhase.CLock);
        }
        
        // Check for 25% threshold to advance to CVote
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 threshold = (cSupply * C_LOCK_THRESHOLD_BPS) / 10000;
        if (liquidationPhase == LiquidationPhase.CLock && totalCLocked >= threshold) {
            liquidationPhase = LiquidationPhase.CVote;
            cVoteStartTime = block.timestamp;
            emit LiquidationPhaseChanged(LiquidationPhase.CLock, LiquidationPhase.CVote);
        }
        
        emit CLocked(user, amount);
    }
    
    function recordVConfirmation(address user, uint256 amount) external {
        if (msg.sender != address(V_TOKEN)) revert OnlyVToken();
        if (liquidationPhase != LiquidationPhase.VConfirm) revert InvalidLiquidationPhase();
        
        vLockedForLiquidation[user] += amount;
        totalVLocked += amount;
        
        emit VLocked(user, amount);
    }
    
    /**
     * @notice Resolve CVote phase after 90 days
     * @dev V3: No acceleration - test only at day 90
     */
    function resolveCVote() external {
        if (liquidationPhase != LiquidationPhase.CVote) revert InvalidLiquidationPhase();
        if (block.timestamp < cVoteStartTime + C_VOTE_DURATION) revert CVoteNotExpired();
        
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 threshold = (cSupply * C_VOTE_THRESHOLD_BPS) / 10000;
        
        if (totalCLocked >= threshold) {
            // Success: advance to VConfirm at next epoch
            liquidationPhase = LiquidationPhase.VConfirm;
            vConfirmEpoch = currentEpoch + 1;
            emit LiquidationPhaseChanged(LiquidationPhase.CVote, LiquidationPhase.VConfirm);
        } else {
            // Failed: back to Normal, C withdrawable
            liquidationPhase = LiquidationPhase.Normal;
            cVoteStartTime = 0;
            emit LiquidationPhaseChanged(LiquidationPhase.CVote, LiquidationPhase.Normal);
        }
    }
    
    /**
     * @notice Resolve VConfirm phase after epoch ends
     * @dev V3: 1 epoch duration instead of 7 days
     */
    function resolveVConfirm() external {
        if (liquidationPhase != LiquidationPhase.VConfirm) revert InvalidLiquidationPhase();
        if (currentEpoch <= vConfirmEpoch) revert VConfirmEpochNotEnded();
        
        uint256 vSupply = V_TOKEN.totalSupply();
        uint256 threshold = (vSupply * V_CONFIRM_THRESHOLD_BPS) / 10000;
        
        if (totalVLocked >= threshold) {
            // Success: liquidation approved
            liquidationPhase = LiquidationPhase.Approved;
            liquidationApprovedTime = block.timestamp;
            cSupplyAtLiquidation = C_TOKEN.totalSupply();
            emit LiquidationPhaseChanged(LiquidationPhase.VConfirm, LiquidationPhase.Approved);
        } else {
            // Failed: back to Normal, C and V withdrawable
            liquidationPhase = LiquidationPhase.Normal;
            cVoteStartTime = 0;
            vConfirmEpoch = 0;
            emit LiquidationPhaseChanged(LiquidationPhase.VConfirm, LiquidationPhase.Normal);
        }
    }
    
    /**
     * @notice Withdraw tokens after failed liquidation
     */
    function withdrawFailedLiquidation() external nonReentrant {
        if (liquidationPhase != LiquidationPhase.Normal) revert InvalidLiquidationPhase();
        
        uint256 cAmount = cLockedForLiquidation[msg.sender];
        uint256 vAmount = vLockedForLiquidation[msg.sender];
        
        if (cAmount == 0 && vAmount == 0) revert NothingToWithdraw();
        
        cLockedForLiquidation[msg.sender] = 0;
        vLockedForLiquidation[msg.sender] = 0;
        
        if (cAmount > 0) {
            totalCLocked -= cAmount;
            IERC20(address(C_TOKEN)).safeTransfer(msg.sender, cAmount);
        }
        if (vAmount > 0) {
            totalVLocked -= vAmount;
            IERC20(address(V_TOKEN)).safeTransfer(msg.sender, vAmount);
        }
        
        emit FailedLiquidationWithdrawn(msg.sender, cAmount, vAmount);
    }
    
    function claimRTokens() external nonReentrant {
        if (liquidationPhase != LiquidationPhase.Approved) revert InvalidLiquidationPhase();
        if (block.timestamp > liquidationApprovedTime + R_CLAIM_WINDOW) revert WindowExpired();
        
        uint256 locked = cLockedForLiquidation[msg.sender];
        if (locked == 0) revert NothingToClaim();
        if (hasClaimedR[msg.sender]) revert NothingToClaim();
        
        hasClaimedR[msg.sender] = true;
        cLockedForLiquidation[msg.sender] = 0;
        totalRClaimed += locked;
        
        R_TOKEN.mint(msg.sender, locked);
        emit RTokensClaimed(msg.sender, locked);
    }
    
    function sweepUnclaimedReceipts() external onlyOwner {
        if (liquidationPhase != LiquidationPhase.Approved) revert InvalidLiquidationPhase();
        if (block.timestamp <= liquidationApprovedTime + R_CLAIM_WINDOW) revert WindowExpired();
        
        uint256 unclaimed = totalCLocked - totalRClaimed;
        if (unclaimed > 0) {
            R_TOKEN.mint(TREASURY, unclaimed);
            emit UnclaimedReceiptsSwept(unclaimed);
        }
        
        liquidationPhase = LiquidationPhase.Closed;
        emit LiquidationPhaseChanged(LiquidationPhase.Approved, LiquidationPhase.Closed);
    }
    
    function withdrawAllNFTs() external {
        if (msg.sender != LIQUIDATION_MULTISIG) revert OnlyMultisig();
        if (liquidationPhase != LiquidationPhase.Approved &&
            liquidationPhase != LiquidationPhase.Closed) {
            revert InvalidLiquidationPhase();
        }
        
        uint256 nftId = masterNftId;
        masterNftId = 0;
        
        VOTING_ESCROW.safeTransferFrom(address(this), LIQUIDATION_MULTISIG, nftId);
        emit NFTsWithdrawn(LIQUIDATION_MULTISIG, nftId);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════
    
    function setAerodromeVoter(address _voter) external onlyOwner {
        if (_voter == address(0)) revert ZeroAddress();
        aerodromeVoter = IVoter(_voter);
        emit AerodromeVoterUpdated(_voter);
    }
    
    function setEpochGovernor(address _governor) external onlyOwner {
        if (_governor == address(0)) revert ZeroAddress();
        epochGovernor = IEpochGovernor(_governor);
        emit EpochGovernorUpdated(_governor);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    function isDepositWindowOpen() external view returns (bool) {
        return _isDepositWindowOpen();
    }
    
    function canExecuteVote() external view returns (bool) {
        return block.timestamp >= votingEndTime && 
               block.timestamp <= votingEndTime + 1 hours &&
               !voteExecutedThisEpoch;
    }
    
    function needsEpochReset() external view returns (bool) {
        return block.timestamp >= epochEndTime;
    }
    
    function canSnapshot() external view returns (bool) {
        return block.timestamp > votingEndTime && 
               block.timestamp < epochEndTime &&
               snapshotEpoch[msg.sender] != currentEpoch;
    }
    
    function pendingNftCount() external view returns (uint256) {
        return pendingNftIds.length;
    }
    
    function registeredPoolCount() external view returns (uint256) {
        return poolRegistry.nextIndex;
    }
    
    function hasPendingConsolidation() external view returns (bool) {
        return pendingNftIds.length > 0;
    }
    
    function canConsolidate() external view returns (bool) {
        return pendingNftIds.length > 0 && block.number > pendingNftBlock;
    }
    
    function getPoolIndex(address pool) external view returns (uint256) {
        return poolRegistry.getIndex(pool);
    }
    
    function getPoolByIndex(uint256 index) external view returns (address) {
        return poolRegistry.getPool(index);
    }
    
    function getPoolWeight(address pool) external view returns (uint256) {
        if (!poolRegistry.isRegistered(pool)) return 0;
        if (weightsEpoch != currentEpoch) return 0;
        return currentWeights.getWeight(storageConfig, poolRegistry.getIndex(pool));
    }
    
    function getStorageStats() external view returns (
        uint256 bitsPerPool,
        uint256 poolsPerSlot,
        uint256 totalSlots,
        uint256 maxPoolIndex,
        uint256 maxWeightPerPool
    ) {
        return DynamicGaugeVoteStorage.getStats(storageConfig);
    }
    
    /**
     * @notice Get liquidation status
     */
    function getLiquidationStatus() external view returns (
        LiquidationPhase phase,
        uint256 cLockedPercent,
        uint256 vLockedPercent,
        uint256 cTargetPercent,
        uint256 vTargetPercent,
        uint256 timeRemaining
    ) {
        phase = liquidationPhase;
        
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 vSupply = V_TOKEN.totalSupply();
        
        cLockedPercent = cSupply > 0 ? (totalCLocked * 10000) / cSupply : 0;
        vLockedPercent = vSupply > 0 ? (totalVLocked * 10000) / vSupply : 0;
        
        if (phase == LiquidationPhase.Normal || phase == LiquidationPhase.CLock) {
            cTargetPercent = C_LOCK_THRESHOLD_BPS;
            vTargetPercent = 0;
            timeRemaining = 0;
        } else if (phase == LiquidationPhase.CVote) {
            cTargetPercent = C_VOTE_THRESHOLD_BPS;
            vTargetPercent = 0;
            uint256 endTime = cVoteStartTime + C_VOTE_DURATION;
            timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
        } else if (phase == LiquidationPhase.VConfirm) {
            cTargetPercent = C_VOTE_THRESHOLD_BPS;
            vTargetPercent = V_CONFIRM_THRESHOLD_BPS;
            timeRemaining = currentEpoch > vConfirmEpoch ? 0 : epochEndTime - block.timestamp;
        } else {
            cTargetPercent = 0;
            vTargetPercent = 0;
            timeRemaining = 0;
        }
    }
    
    function daysRemainingInCVote() external view returns (uint256) {
        if (liquidationPhase != LiquidationPhase.CVote) return 0;
        
        uint256 endTime = cVoteStartTime + C_VOTE_DURATION;
        if (block.timestamp >= endTime) return 0;
        
        return (endTime - block.timestamp) / 1 days;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════
    
    function _isDepositWindowOpen() internal view returns (bool) {
        uint256 dayOfWeek = ((block.timestamp / 1 days) + 4) % 7;
        uint256 timeInDay = block.timestamp % 1 days;
        uint256 hour = timeInDay / 1 hours;
        uint256 minute = (timeInDay % 1 hours) / 1 minutes;
        
        if (dayOfWeek == 3 && (hour > 21 || (hour == 21 && minute >= 45))) {
            return false;
        }
        if (dayOfWeek == 4 && hour == 0 && minute < 1) {
            return false;
        }
        return true;
    }
    
    function _getNextThursday() internal view returns (uint256) {
        uint256 dayOfWeek = ((block.timestamp / 1 days) + 4) % 7;
        uint256 daysUntilThursday;
        
        if (dayOfWeek == 4) {
            daysUntilThursday = 7;
        } else if (dayOfWeek < 4) {
            daysUntilThursday = 4 - dayOfWeek;
        } else {
            daysUntilThursday = 11 - dayOfWeek;
        }
        
        uint256 todayStart = (block.timestamp / 1 days) * 1 days;
        return todayStart + (daysUntilThursday * 1 days);
    }
}
