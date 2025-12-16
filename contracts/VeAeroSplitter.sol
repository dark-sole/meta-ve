// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./Interfaces.sol";
import "./IVoteLib.sol";

/**
 * @title VeAeroSplitter V6
 * @notice Wraps veAERO NFTs into fungible V-AERO and C-AERO tokens
 * @dev 
 *      
 * Architecture:
 *      - VeAeroLiquidation: Tracks C/V locks, phase transitions
 *      - VeAeroBribes: Snapshot/claim for bribe distribution
 *      - VeAeroSplitter: Deposits, voting, fee/rebase/meta claims, NFT custody
 *      
 * Revenue Streams:
 *      1. EMISSIONS (Aerodrome weekly veAERO rebase):
 *         - Master NFT locked amount grows automatically
 *         - C-AERO holders call claimRebase() → receive NEW V+C tokens
 *      
 *      2. TRADING FEES (liquid AERO from pools):
 *         - collectFees() claims AERO → 50% to C holders, 50% to Meta
 *      
 *      3. META REWARDS:
 *         - C-AERO holders call claimMeta() → receive META tokens
 *      
 *      4. BRIBES (handled by VeAeroBribes):
 *         - collectBribes() claims from Aerodrome, tokens stay here
 *         - VeAeroBribes handles snapshot/claim via pullBribeToken()
 */
contract VeAeroSplitter is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public constant TOKENISYS_FEE_BPS = 100;    // 1% to Tokenisys
    uint256 public constant META_FEE_BPS = 900;         // 9% to meta
    uint256 public constant MIN_DEPOSIT_AMOUNT = 1e18;  // 1 AERO
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_VOTE_POOLS = 30;        // Aerodrome limit
    uint256 public constant POOL_BUFFER = 100;          // Extra slots for growth
    uint256 public constant MAX_CONSOLIDATE_PER_TX = 50;// Batch limit
    uint256 public constant R_CLAIM_WINDOW = 7 days;    // Window to claim R-tokens
    
    // ═══════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════
    
    IVotingEscrow public immutable VOTING_ESCROW;
    IERC20 public immutable AERO_TOKEN;
    IERC20 public immutable META_TOKEN;
    IVToken public immutable V_TOKEN;
    ICToken public immutable C_TOKEN;
    IRToken public immutable R_TOKEN;
    address public immutable TOKENISYS;
    address public immutable LIQUIDATION_MULTISIG;
    IVeAeroLiquidation public immutable LIQUIDATION;
    address public immutable BRIBES; 
    
    // ═══════════════════════════════════════════════════════════════
    // EXTERNAL CONTRACTS (Mutable)
    // ═══════════════════════════════════════════════════════════════
    
    IVoter public aerodromeVoter;
    IEpochGovernor public epochGovernor;
    IVoteLib public voteLib;
    
    
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
    // LIQUID FEE CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public globalFeeIndex;
    mapping(address => uint256) public userFeeCheckpoint;
    
    // ═══════════════════════════════════════════════════════════════
    // REBASE STATE (Aerodrome emissions → V+C minting)
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public globalRebaseIndex;
    uint256 public adjustedRebaseBacking;
    mapping(address => uint256) public userRebaseCheckpoint;
    uint256 public lastTrackedLocked;
    
    // ═══════════════════════════════════════════════════════════════
    // META REWARD DISTRIBUTION
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public globalMetaIndex;
    mapping(address => uint256) public userMetaCheckpoint;
    uint256 public totalMetaIndexed;
    
    // ═══════════════════════════════════════════════════════════════
    // BRIBE WHITELIST (tokens held here, claims via VeAeroBribes)
    // ═══════════════════════════════════════════════════════════════
   
    mapping(address => bool) public isWhitelistedBribe;
    mapping(address => uint256) public bribeWhitelistEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // R-TOKEN CLAIM STATE (liquidation finalization)
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public cSupplyAtLiquidation;
    uint256 public totalRClaimed;
    mapping(address => bool) public hasClaimedR;
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    // Config events
    event StorageConfigured(uint256 maxPools, uint256 bitsPerPool, uint256 poolsPerSlot, uint256 numSlots, uint256 maxWeightPerPool);
    event StorageExpanded(uint256 oldMaxPools, uint256 newMaxPools);
    
    // Deposit events
    event NFTDeposited(address indexed user, uint256 indexed tokenId, uint256 lockedAmount, uint256 userAmount, uint256 tokenisysAmount, uint256 metaAmount);
    event MasterNftSet(uint256 indexed tokenId);
    event NFTConsolidated(uint256 indexed sourceId, uint256 indexed masterId);
    event PendingNftAdded(uint256 indexed tokenId, uint256 batchSize);
    event BatchConsolidated(uint256 count, uint256 indexed masterNftId);
    
    // Voting events
    event EmissionsVoteRecorded(address indexed user, uint256 indexed epoch, int8 choice, uint256 amount);
    event GaugeVoteExecuted(address[] pools, uint256[] weights, uint256 activeTotal, uint256 passiveTotal);
    event EmissionsVoteExecuted(uint256 proposalId, uint8 support, uint256 totalVotes);
    event PoolRegistered(address indexed pool, uint256 indexed index);
    
    // Epoch events
    event EpochReset(uint256 indexed newEpoch, uint256 newEndTime);
    event VotingWindowSet(uint256 indexed epoch, uint256 votingStart, uint256 votingEnd, uint256 epochEnd);
    
    // Fee claim events
    event FeesCollected(uint256 totalAero, uint256 holderShare, uint256 metaShare, uint256 newFeeIndex);
    event FeesClaimed(address indexed user, uint256 amount);
    
    // META reward events
    event MetaCollected(uint256 amount, uint256 newMetaIndex);
    event MetaClaimed(address indexed user, uint256 amount);
    
    // Bribe events
    event BribeTokenWhitelisted(address indexed token, uint256 epoch);
    event BribeTokenPulled(address indexed token, address indexed to, uint256 amount);
    
    // Transfer settlement events
    event FeesSweptToTokenisys(address indexed from, uint256 amount);
    event MetaSweptToTokenisys(address indexed from, uint256 amount);
    event RebaseSweptToTokenisys(address indexed from, uint256 amount);
    
    // Rebase events
    event RebaseClaimed(address indexed user, uint256 vAmount, uint256 cAmount);
    event RebaseIndexUpdated(uint256 growth, uint256 newGlobalIndex, uint256 totalBacking);
    event UserRebaseCheckpointSet(address indexed user, uint256 checkpoint, uint256 globalIndex);
    
    // Liquidation finalization events (R-token, NFT withdrawal)
    event RTokensClaimed(address indexed user, uint256 amount);
    event UnclaimedReceiptsSwept(uint256 amount);
    event NFTsWithdrawn(address indexed to, uint256 tokenId);
    
    // Admin events
    event AerodromeVoterUpdated(address indexed newVoter);
    event EpochGovernorUpdated(address indexed newGovernor);
    event VoteLibUpdated(address indexed voteLib);
    
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
    error OnlyMultisig();
    error OnlyOwnerOrMultisig();
    error OnlyCToken();
    error OnlyBribes();
    error InvalidGauge(address pool);
    error GaugeNotAlive();
    error LiquidationInProgress();
    error LiquidationNotApproved();
    error WindowExpired();
    error NotWhitelistedBribe();
    error ProtocolTokenNotAllowed();
    error VotingNotEnded();
    
    // ═══════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Prevents operations during active liquidation
     * @dev Reads from VeAeroLiquidation contract
     */
    modifier notInLiquidation() {
        _checkNotInLiquidation();
        _;
    }

    function _checkNotInLiquidation() internal view {
        if (LIQUIDATION.isLiquidationApproved()) {
            revert LiquidationInProgress();
        }
    }   
    
    modifier ensureCurrentEpoch() {
        _ensureCurrentEpoch();
        _;
    }

    function _ensureCurrentEpoch() internal {
        if (block.timestamp >= epochEndTime) {
            _resetEpoch();
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR (12 parameters)
    // ═══════════════════════════════════════════════════════════════
    
    constructor(
        address _votingEscrow,
        address _aeroToken,
        address _metaToken,
        address _vToken,
        address _cToken,
        address _rToken,
        address _tokenisys,
        address _liquidationMultisig,
        address _liquidation,
        address _bribes,              
        address _aerodromeVoter,
        address _epochGovernor
    ) Ownable(msg.sender) {
        if (_votingEscrow == address(0) || _aeroToken == address(0) || _metaToken == address(0) || _vToken == address(0) || _cToken == address(0) || _rToken == address(0) || _tokenisys == address(0) || _liquidationMultisig == address(0) || _liquidation == address(0) || _bribes == address(0) || _aerodromeVoter == address(0) || _epochGovernor == address(0)) revert ZeroAddress();
        
        VOTING_ESCROW = IVotingEscrow(_votingEscrow);
        AERO_TOKEN = IERC20(_aeroToken);
        META_TOKEN = IERC20(_metaToken);
        V_TOKEN = IVToken(_vToken);
        C_TOKEN = ICToken(_cToken);
        R_TOKEN = IRToken(_rToken);
        TOKENISYS = _tokenisys;
        LIQUIDATION_MULTISIG = _liquidationMultisig;
        LIQUIDATION = IVeAeroLiquidation(_liquidation);
        BRIBES = _bribes;
        aerodromeVoter = IVoter(_aerodromeVoter);
        epochGovernor = IEpochGovernor(_epochGovernor);
        
        // Initialize epoch
        currentEpoch = 1;
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        globalFeeIndex = PRECISION;
        globalMetaIndex = PRECISION;
        globalRebaseIndex = PRECISION;
        
        emit EpochReset(1, epochEndTime);
        emit VotingWindowSet(1, votingStartTime, votingEndTime, epochEndTime);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // EPOCH RESET
    // ═══════════════════════════════════════════════════════════════
    
    function resetEpoch() external notInLiquidation {
        if (block.timestamp < epochEndTime) revert NotNewEpoch();
        _resetEpoch();
    }
    
    function _resetEpoch() internal {
        currentEpoch++;
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        
        voteExecutedThisEpoch = false;
        emissionsDecreaseTotal = 0;
        emissionsHoldTotal = 0;
        emissionsIncreaseTotal = 0;
        
        _updateRebaseIndex();
        
        emit EpochReset(currentEpoch, epochEndTime);
        emit VotingWindowSet(currentEpoch, votingStartTime, votingEndTime, epochEndTime);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // NFT RECEIVER
    // ═══════════════════════════════════════════════════════════════
    
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // DEPOSITS
    // ═══════════════════════════════════════════════════════════════
    
    function depositVeAero(uint256 tokenId) external nonReentrant notInLiquidation ensureCurrentEpoch {
        if (!_isDepositWindowOpen()) revert DepositsDisabled();
        if (VOTING_ESCROW.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
        if (VOTING_ESCROW.voted(tokenId)) revert NFTAlreadyVoted();
        
        IVotingEscrow.LockedBalance memory locked = VOTING_ESCROW.locked(tokenId);
        if (!locked.isPermanent) revert OnlyPermanentLocksAccepted();
        
        uint256 lockedAmount = uint256(uint128(locked.amount));
        if (lockedAmount < MIN_DEPOSIT_AMOUNT) revert AmountTooSmall();
        
        // Claim any pending rebase before deposit changes backing
        if (userRebaseCheckpoint[msg.sender] > 0 && 
            userRebaseCheckpoint[msg.sender] < globalRebaseIndex &&
            C_TOKEN.balanceOf(msg.sender) > 0) {
            _claimRebaseInternal(msg.sender);
        }
        
        // Calculate fee splits
        uint256 tokenisysAmount = (lockedAmount * TOKENISYS_FEE_BPS) / 10000;
        uint256 metaAmount = (lockedAmount * META_FEE_BPS) / 10000;
        uint256 userAmount = lockedAmount - tokenisysAmount - metaAmount;
        
        // Transfer NFT
        VOTING_ESCROW.safeTransferFrom(msg.sender, address(this), tokenId);
        
        // Handle master NFT setup
        if (masterNftId == 0) {
            masterNftId = tokenId;
            lastTrackedLocked = lockedAmount;
            emit MasterNftSet(tokenId);
        } else {
            pendingNftIds.push(tokenId);
            pendingNftBlock = block.number;
            emit PendingNftAdded(tokenId, pendingNftIds.length);
        }
        
        // ALWAYS update backing for ALL deposits
        adjustedRebaseBacking += lockedAmount;
        
        // Initialize checkpoints for new depositors
        if (userFeeCheckpoint[msg.sender] == 0) {
            userFeeCheckpoint[msg.sender] = globalFeeIndex;
        }
        if (userMetaCheckpoint[msg.sender] == 0) {
            userMetaCheckpoint[msg.sender] = globalMetaIndex;
        }
        if (userRebaseCheckpoint[msg.sender] == 0) {
            userRebaseCheckpoint[msg.sender] = globalRebaseIndex;
            emit UserRebaseCheckpointSet(msg.sender, globalRebaseIndex, globalRebaseIndex);
        }
        
        // Mint tokens
        V_TOKEN.mint(msg.sender, userAmount);
        C_TOKEN.mint(msg.sender, lockedAmount - tokenisysAmount);
        
        V_TOKEN.mint(TOKENISYS, tokenisysAmount);
        C_TOKEN.mint(TOKENISYS, tokenisysAmount);
        
        V_TOKEN.mint(address(META_TOKEN), metaAmount);
        
        emit NFTDeposited(msg.sender, tokenId, lockedAmount, userAmount, tokenisysAmount, metaAmount);
    }
    
    function consolidatePending() external nonReentrant notInLiquidation {
        if (masterNftId == 0) revert NoMasterNft();
        if (pendingNftIds.length == 0) revert NoPendingNfts();
        if (block.number <= pendingNftBlock) revert PendingNotReady();
        
        _consolidateAll();
    }
    
    function _consolidateAll() internal {
        uint256 count = pendingNftIds.length;
        if (count > MAX_CONSOLIDATE_PER_TX) {
            count = MAX_CONSOLIDATE_PER_TX;
        }
        
        uint256[] memory nftsToMerge = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            nftsToMerge[i] = pendingNftIds[pendingNftIds.length - 1];
            pendingNftIds.pop();
        }
        
        for (uint256 i = 0; i < count; i++) {
            VOTING_ESCROW.unlockPermanent(nftsToMerge[i]);
            VOTING_ESCROW.merge(nftsToMerge[i], masterNftId);
            emit NFTConsolidated(nftsToMerge[i], masterNftId);
        }
        
        lastTrackedLocked = uint256(uint128(VOTING_ESCROW.locked(masterNftId).amount));
        
        emit BatchConsolidated(count, masterNftId);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // GAUGE VOTING
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Execute gauge votes using aggregated votes from VToken
     * @dev Callable by anyone during execution window
     */
     function executeGaugeVote() external nonReentrant notInLiquidation {
    // Check if already executed
    if (voteExecutedThisEpoch) revert VoteAlreadyExecuted();
    
    // Check execution window (timing provides security)
    if (block.timestamp <= votingEndTime) revert VotingNotEnded();
    if (block.timestamp > epochEndTime) revert ExecutionWindowClosed();
    
    // Get aggregated votes from VToken
    (address[] memory pools, uint256[] memory weights) = V_TOKEN.getAggregatedVotes();
    
    // Handle empty votes properly
    if (pools.length == 0) {
        // Check if there are passive votes but no active votes
        uint256 passiveVotes = V_TOKEN.totalPassiveVotes();
        if (passiveVotes > 0) {
            revert NoVotesToExecute();  // Can't distribute passive without active
        }
        emit GaugeVoteExecuted(pools, weights, 0, 0);
        voteExecutedThisEpoch = true;
        return;
    }
    
    // Execute vote
    if (pools.length <= MAX_VOTE_POOLS) {
        // Direct execution (≤30 pools)
        aerodromeVoter.vote(masterNftId, pools, weights);
    } else {
        // Truncate to top 30 pools
        address[] memory top30Pools = new address[](MAX_VOTE_POOLS);
        uint256[] memory top30Weights = new uint256[](MAX_VOTE_POOLS);
        
        for (uint256 i = 0; i < MAX_VOTE_POOLS; i++) {
            top30Pools[i] = pools[i];
            top30Weights[i] = weights[i];
        }
        
        aerodromeVoter.vote(masterNftId, top30Pools, top30Weights);
    }
    
    // Mark vote as executed BEFORE reset
    voteExecutedThisEpoch = true;
    
    // Capture totals BEFORE reset (convert from wei to whole tokens for event)
    uint256 activeVotesThisEpoch = totalVLockedForVoting();  // Capture before reset
    uint256 passiveVotesThisEpoch = V_TOKEN.totalPassiveVotes() / 1e18;
    
    // Reset VToken for next epoch
    V_TOKEN.resetVotesForNewEpoch();
    
    // Emit with actual totals from this epoch (both in whole tokens)
    emit GaugeVoteExecuted(pools, weights, activeVotesThisEpoch, passiveVotesThisEpoch);
}

    // ═══════════════════════════════════════════════════════════════
    // EMISSIONS VOTING
    // ═══════════════════════════════════════════════════════════════
    
    function recordEmissionsVote(
        address user,
        int8 choice,
        uint256 amount
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
        uint8 support = 1; // Hold
        
        if (emissionsDecreaseTotal > maxVotes) {
            maxVotes = emissionsDecreaseTotal;
            support = 0; // Against
        }
        if (emissionsIncreaseTotal > maxVotes) {
            maxVotes = emissionsIncreaseTotal;
            support = 2; // For
        }
        
        if (maxVotes == 0) revert NoVotesToExecute();
        
        epochGovernor.castVote(proposalId, support);
        
        emit EmissionsVoteExecuted(proposalId, support, maxVotes);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // FEE COLLECTION & CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    function collectFees(
        address[] calldata feeDistributors,
        address[][] calldata tokens
    ) external nonReentrant notInLiquidation {
        if (masterNftId == 0) revert NoMasterNft();
        
        uint256 balanceBefore = AERO_TOKEN.balanceOf(address(this));
        
        aerodromeVoter.claimFees(feeDistributors, tokens, masterNftId);
        
        uint256 balanceAfter = AERO_TOKEN.balanceOf(address(this));
        uint256 collected = balanceAfter - balanceBefore;
        
        if (collected == 0) return;
        
        uint256 holderShare = collected / 2;
        uint256 metaShare = collected - holderShare;
        
        uint256 cSupply = C_TOKEN.totalSupply();
        if (cSupply > 0) {
            globalFeeIndex += (holderShare * PRECISION) / cSupply;
        }
        
        if (metaShare > 0) {
            AERO_TOKEN.approve(address(META_TOKEN), metaShare);
            IMeta(address(META_TOKEN)).receiveFees(metaShare);
        }
        
        emit FeesCollected(collected, holderShare, metaShare, globalFeeIndex);
    }
    
    function claimFees() external nonReentrant returns (uint256 owed) {
        uint256 checkpoint = userFeeCheckpoint[msg.sender];
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        
        uint256 balance = C_TOKEN.balanceOf(msg.sender);
        owed = (balance * (globalFeeIndex - checkpoint)) / PRECISION;
        
        userFeeCheckpoint[msg.sender] = globalFeeIndex;
        
        if (owed > 0) {
            AERO_TOKEN.safeTransfer(msg.sender, owed);
        }
        
        emit FeesClaimed(msg.sender, owed);
    }
    
    function pendingFees(address user) external view returns (uint256) {
        uint256 checkpoint = userFeeCheckpoint[user];
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        uint256 balance = C_TOKEN.balanceOf(user);
        return (balance * (globalFeeIndex - checkpoint)) / PRECISION;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // META COLLECTION & CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    function collectMeta() external nonReentrant notInLiquidation {
        uint256 balance = META_TOKEN.balanceOf(address(this));
        if (balance == 0) return;
        
        uint256 newAmount = balance - totalMetaIndexed;
        if (newAmount == 0) return;
        
        uint256 cSupply = C_TOKEN.totalSupply();
        if (cSupply > 0) {
            globalMetaIndex += (newAmount * PRECISION) / cSupply;
        }
        
        totalMetaIndexed = balance;
        
        emit MetaCollected(newAmount, globalMetaIndex);
    }
    
    function claimMeta() external nonReentrant returns (uint256 owed) {
        uint256 checkpoint = userMetaCheckpoint[msg.sender];
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        
        uint256 balance = C_TOKEN.balanceOf(msg.sender);
        owed = (balance * (globalMetaIndex - checkpoint)) / PRECISION;
        
        userMetaCheckpoint[msg.sender] = globalMetaIndex;
        
        if (owed > 0) {
            totalMetaIndexed -= owed;
            META_TOKEN.safeTransfer(msg.sender, owed);
        }
        
        emit MetaClaimed(msg.sender, owed);
    }
    
    function pendingMeta(address user) external view returns (uint256) {
        uint256 checkpoint = userMetaCheckpoint[user];
        if (checkpoint == 0) {
            checkpoint = PRECISION;
        }
        uint256 balance = C_TOKEN.balanceOf(user);
        return (balance * (globalMetaIndex - checkpoint)) / PRECISION;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // REBASE CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    function updateRebaseIndex() external notInLiquidation {
        _updateRebaseIndex();
    }
    
    function _updateRebaseIndex() internal {
        if (masterNftId == 0) return;
        
        uint256 currentLocked = uint256(uint128(VOTING_ESCROW.locked(masterNftId).amount));
        
        if (currentLocked > lastTrackedLocked && adjustedRebaseBacking > 0) {
            uint256 growth = currentLocked - lastTrackedLocked;
            globalRebaseIndex += (growth * PRECISION) / adjustedRebaseBacking;
            emit RebaseIndexUpdated(growth, globalRebaseIndex, adjustedRebaseBacking);
        }
        
        lastTrackedLocked = currentLocked; 
    }
    
    function claimRebase() external nonReentrant notInLiquidation {
        _claimRebaseInternal(msg.sender);
    }
    
    function _claimRebaseInternal(address user) internal returns (uint256 netAmount) {
        _updateRebaseIndex();
        
        uint256 cBalance = C_TOKEN.balanceOf(user);
        uint256 checkpoint = userRebaseCheckpoint[user];
        
        if (checkpoint == 0) {
            userRebaseCheckpoint[user] = globalRebaseIndex;
            emit UserRebaseCheckpointSet(user, globalRebaseIndex, globalRebaseIndex);
            revert NothingToClaim();
        }
        
        if (checkpoint >= globalRebaseIndex || cBalance == 0) {
            revert NothingToClaim();
        }
        
        uint256 indexDelta = globalRebaseIndex - checkpoint;
        uint256 grossAmount = (cBalance * indexDelta) / PRECISION;

        uint256 tokenisysAmount = (grossAmount * TOKENISYS_FEE_BPS) / 10000;  // 1%
        uint256 metaAmount = (grossAmount * META_FEE_BPS) / 10000;            // 9%
        uint256 userVAmount = grossAmount - tokenisysAmount - metaAmount;     // 90%
        uint256 userCAmount = grossAmount - tokenisysAmount; 
        
        if (userVAmount == 0) revert NothingToClaim();

        userRebaseCheckpoint[user] = globalRebaseIndex;

        // Mint V: 90% user, 1% Tokenisys, 9% META
        V_TOKEN.mint(user, userVAmount);
        V_TOKEN.mint(TOKENISYS, tokenisysAmount);
        V_TOKEN.mint(address(META_TOKEN), metaAmount);

        // Mint C: 99% user, 1% Tokenisys
        C_TOKEN.mint(user, userCAmount);
        C_TOKEN.mint(TOKENISYS, tokenisysAmount);

        adjustedRebaseBacking += grossAmount;

        netAmount = userVAmount;

        emit RebaseClaimed(user, userVAmount, userCAmount);
    }
    
    function pendingRebase(address user) external view returns (uint256) {
        uint256 checkpoint = userRebaseCheckpoint[user];
        if (checkpoint == 0) return 0;
        
        uint256 cBalance = C_TOKEN.balanceOf(user);
        uint256 grossOwed = (cBalance * (globalRebaseIndex - checkpoint)) / PRECISION;
        
        // Return user's V amount (90%)
        uint256 tokenisysAmount = (grossOwed * TOKENISYS_FEE_BPS) / 10000;
        uint256 metaAmount = (grossOwed * META_FEE_BPS) / 10000;
        return grossOwed - tokenisysAmount - metaAmount;
            }
    
    function getAllPendingClaims(address user) external view returns (
        uint256 rebaseAmount,
        uint256 feeAmount,
        uint256 metaAmount
    ) {
        // Rebase
        uint256 rebaseCheckpoint = userRebaseCheckpoint[user];
        if (rebaseCheckpoint > 0) {
            uint256 cBalance = C_TOKEN.balanceOf(user);
            uint256 grossRebase = (cBalance * (globalRebaseIndex - rebaseCheckpoint)) / PRECISION;
            uint256 tokenisysAmount = (grossRebase * TOKENISYS_FEE_BPS) / 10000;  // 1%
            metaAmount = (grossRebase * META_FEE_BPS) / 10000;            // 9%
            rebaseAmount = grossRebase - tokenisysAmount - metaAmount;            // 90%
       }
        
        // Fees
        uint256 feeCheckpoint = userFeeCheckpoint[user];
        if (feeCheckpoint == 0) feeCheckpoint = PRECISION;
        uint256 cBalanceFee = C_TOKEN.balanceOf(user);
        feeAmount = (cBalanceFee * (globalFeeIndex - feeCheckpoint)) / PRECISION;
        
        // Meta
        uint256 metaCheckpoint = userMetaCheckpoint[user];
        if (metaCheckpoint == 0) metaCheckpoint = PRECISION;
        uint256 cBalanceMeta = C_TOKEN.balanceOf(user);
        metaAmount = (cBalanceMeta * (globalMetaIndex - metaCheckpoint)) / PRECISION;
    }


   

   


    
    // ═══════════════════════════════════════════════════════════════
    // TRANSFER SETTLEMENT (called by CToken)
    // ═══════════════════════════════════════════════════════════════
    
    function onCTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) external {
        if (msg.sender != address(C_TOKEN)) revert OnlyCToken();
        if (from == address(0) || to == address(0)) return;  // Guard for mint/burn
        
        // Calculate unclaimed amounts for sender
        uint256 fromBalance = C_TOKEN.balanceOf(from);
        
        uint256 fromFeeCheckpoint = userFeeCheckpoint[from];
        if (fromFeeCheckpoint == 0) fromFeeCheckpoint = PRECISION;
        uint256 unclaimedFees = (fromBalance * (globalFeeIndex - fromFeeCheckpoint)) / PRECISION;
        
        uint256 fromMetaCheckpoint = userMetaCheckpoint[from];
        if (fromMetaCheckpoint == 0) fromMetaCheckpoint = PRECISION;
        uint256 unclaimedMeta = (fromBalance * (globalMetaIndex - fromMetaCheckpoint)) / PRECISION;
        
        uint256 fromRebaseCheckpoint = userRebaseCheckpoint[from];
        uint256 unclaimedRebase = 0;
        if (fromRebaseCheckpoint > 0) {
            unclaimedRebase = (fromBalance * (globalRebaseIndex - fromRebaseCheckpoint)) / PRECISION;
        }
        
        // Calculate weighted average checkpoints for receiver
        uint256 toBalance = C_TOKEN.balanceOf(to);
        
        uint256 toFeeCheckpoint = userFeeCheckpoint[to];
        if (toFeeCheckpoint == 0) toFeeCheckpoint = PRECISION;
        
        uint256 toMetaCheckpoint = userMetaCheckpoint[to];
        if (toMetaCheckpoint == 0) toMetaCheckpoint = PRECISION;
        
        uint256 toRebaseCheckpoint = userRebaseCheckpoint[to];
        if (toRebaseCheckpoint == 0) toRebaseCheckpoint = globalRebaseIndex;
        
        uint256 newTotal = toBalance + amount;
        uint256 newToFeeCheckpoint = toFeeCheckpoint;
        uint256 newToMetaCheckpoint = toMetaCheckpoint;
        uint256 newToRebaseCheckpoint = toRebaseCheckpoint;
        
        if (newTotal > 0) {
            newToFeeCheckpoint = ((toBalance * toFeeCheckpoint) + (amount * globalFeeIndex)) / newTotal;
            newToMetaCheckpoint = ((toBalance * toMetaCheckpoint) + (amount * globalMetaIndex)) / newTotal;
            newToRebaseCheckpoint = ((toBalance * toRebaseCheckpoint) + (amount * globalRebaseIndex)) / newTotal;
        }
        
        // Update checkpoints
        userFeeCheckpoint[from] = globalFeeIndex;
        userMetaCheckpoint[from] = globalMetaIndex;
        userRebaseCheckpoint[from] = globalRebaseIndex;
        
        userFeeCheckpoint[to] = newToFeeCheckpoint;
        userMetaCheckpoint[to] = newToMetaCheckpoint;
        userRebaseCheckpoint[to] = newToRebaseCheckpoint;
        
        if (unclaimedMeta > 0) {
            totalMetaIndexed -= unclaimedMeta;
        }
        
        // Transfer unclaimed to Tokenisys
        if (unclaimedFees > 0) {
            AERO_TOKEN.safeTransfer(TOKENISYS, unclaimedFees);
            emit FeesSweptToTokenisys(from, unclaimedFees);
        }
        
        if (unclaimedMeta > 0) {
            META_TOKEN.safeTransfer(TOKENISYS, unclaimedMeta);
            emit MetaSweptToTokenisys(from, unclaimedMeta);
        }
        
        if (unclaimedRebase > 0) {
            V_TOKEN.mint(TOKENISYS, unclaimedRebase);
            C_TOKEN.mint(TOKENISYS, unclaimedRebase);
            adjustedRebaseBacking += unclaimedRebase;
            emit RebaseSweptToTokenisys(from, unclaimedRebase);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // BRIBE COLLECTION & PULL 
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Collect bribes from Aerodrome, tokens stay in this contract
     * @dev Whitelists bribe tokens for VeAeroBribes to pull
     */
    function collectBribes(
        address[] calldata bribes,
        address[][] calldata tokens
    ) external nonReentrant notInLiquidation {
        if (masterNftId == 0) revert NoMasterNft();
        
        aerodromeVoter.claimBribes(bribes, tokens, masterNftId);
        
        for (uint256 i = 0; i < bribes.length; i++) {
            for (uint256 j = 0; j < tokens[i].length; j++) {
                address token = tokens[i][j];
                
                // Skip protocol tokens
                if (token == address(AERO_TOKEN)) continue;
                
                // Whitelist for this epoch
                if (bribeWhitelistEpoch[token] != currentEpoch) {
                    isWhitelistedBribe[token] = true;
                    bribeWhitelistEpoch[token] = currentEpoch;
                    emit BribeTokenWhitelisted(token, currentEpoch);
                }
            }
        }
    }
    
    /**
     * @notice Pull bribe tokens to recipient (called by VeAeroBribes only)
     * @dev Security checks:
     *      1. Only BRIBES contract can call
     *      2. Cannot pull AERO, META, V, C, or R tokens
     *      3. Token must be whitelisted for current epoch
     * @param token Bribe token address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function pullBribeToken(address token, address to, uint256 amount) external {
        // Only VeAeroBribes can call
        if (msg.sender != BRIBES) revert OnlyBribes();
        
        // Cannot pull protocol tokens
        if (token == address(AERO_TOKEN)) revert ProtocolTokenNotAllowed();
        
        // Must be whitelisted for current epoch
        if (!isWhitelistedBribe[token]) revert NotWhitelistedBribe();
        if (bribeWhitelistEpoch[token] != currentEpoch) revert NotWhitelistedBribe();
        
        // Transfer to recipient
        IERC20(token).safeTransfer(to, amount);
        
        emit BribeTokenPulled(token, to, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // LIQUIDATION FINALIZATION (R-Token, NFT Withdrawal)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Claim R-Tokens after liquidation approved
     * @dev Users get R-Tokens proportional to their C-AERO locked
     */
    function claimRTokens() external nonReentrant {
        if (!LIQUIDATION.isLiquidationApproved()) revert LiquidationNotApproved();
        
        uint256 approvedTime = LIQUIDATION.getLiquidationApprovedTime();
        if (block.timestamp > approvedTime + R_CLAIM_WINDOW) revert WindowExpired();
        
        uint256 locked = LIQUIDATION.getUserCLocked(msg.sender);
        if (locked == 0) revert NothingToClaim();
        if (hasClaimedR[msg.sender]) revert NothingToClaim();
        
        // Snapshot C supply on first claim
        if (cSupplyAtLiquidation == 0) {
            cSupplyAtLiquidation = C_TOKEN.totalSupply();
        }
        
        hasClaimedR[msg.sender] = true;
        totalRClaimed += locked;
        
        R_TOKEN.mint(msg.sender, locked);
        emit RTokensClaimed(msg.sender, locked);
    }
    
    /**
     * @notice Sweep unclaimed R-Token receipts to Tokenisys
     * @dev Only callable after claim window expires
     */
    function sweepUnclaimedReceipts() external {
        if (msg.sender != owner() && msg.sender != LIQUIDATION_MULTISIG) revert OnlyOwnerOrMultisig();
        if (!LIQUIDATION.isLiquidationApproved()) revert LiquidationNotApproved();
        
        uint256 approvedTime = LIQUIDATION.getLiquidationApprovedTime();
        if (block.timestamp <= approvedTime + R_CLAIM_WINDOW) revert WindowExpired();
        
        uint256 totalLocked = LIQUIDATION.getTotalCLocked();
        uint256 unclaimed = totalLocked - totalRClaimed;
        
        if (unclaimed > 0) {
            R_TOKEN.mint(TOKENISYS, unclaimed);
            emit UnclaimedReceiptsSwept(unclaimed);
        }
        
        // Mark liquidation as closed in external contract
        LIQUIDATION.markClosed();
    }
    
    /**
     * @notice Withdraw master NFT after liquidation closed
     * @dev Only callable by liquidation multisig
     */


    function withdrawAllNFTs() external {
        if (msg.sender != LIQUIDATION_MULTISIG) revert OnlyMultisig();
        
        (IVeAeroLiquidation.LiquidationPhase phase,,,,, ) = 
            LIQUIDATION.getLiquidationStatus(currentEpoch, epochEndTime);
        
        if (phase != IVeAeroLiquidation.LiquidationPhase.Closed) {
            revert LiquidationNotApproved();
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
    /**
     * @notice Set VoteLib address for multi-NFT vote distribution
     * @dev Owner only (will be MSIG after ownership transfer)
     * @param _voteLib VoteLib contract address (address(0) to disable)
     */
    function setVoteLib(address _voteLib) external onlyOwner {
        voteLib = IVoteLib(_voteLib);
        emit VoteLibUpdated(_voteLib);
    }


    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    function isDepositWindowOpen() external view returns (bool) {
        return _isDepositWindowOpen();
    }
    
    
    /**
     * @notice Check if liquidation is active (for VeAeroBribes)
     */
    function isLiquidationActive() external view returns (bool) {
        return LIQUIDATION.isLiquidationApproved();
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
    /**
    * @notice Check if pool has valid gauge in Aerodrome
    * @param pool Pool address to check
    * @return bool True if gauge exists and is alive
    */
    function isValidGauge(address pool) public view returns (bool) {
        address gauge = aerodromeVoter.gauges(pool);
        if (gauge == address(0)) return false;
        return aerodromeVoter.isAlive(gauge);
    }
    function validateGauge(address pool) external view {
        if (!isValidGauge(pool)) revert InvalidGauge(pool);
    }

    /**
     * @notice Get current active votes (computed dynamically)
     * @return Active votes in whole tokens
     */
    function totalVLockedForVoting() public view returns (uint256) {
        return V_TOKEN.totalGaugeVotedThisEpoch() / 1e18;
    }
    
    /**
     * @notice Get current passive votes in whole tokens
     * @return Passive votes in whole tokens
     */
    function totalPassiveVotes() public view returns (uint256) {
        return V_TOKEN.totalPassiveVotes() / 1e18;
    }
}

