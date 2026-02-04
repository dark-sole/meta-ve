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
 * @title VeAeroSplitter DELTA
 * @notice Wraps veAERO NFTs into fungible V-AERO and C-AERO tokens
 * @dev 
 *      
 * Architecture:
 *      - VeAeroLiquidation: Tracks C/V locks, phase transitions
 *      - VeAeroBribes: Snapshot/claim for bribe distribution
 *      - VeAeroSplitter: Deposits, voting, fee/rebase claims, NFT custody
 *      - FeeSwapper: Converts non-AERO fee tokens to AERO (DELTA)
 *      
 * Revenue Streams:
 *      1. REBASE (Aerodrome weekly veAERO emissions):
 *         - Master NFT locked amount grows automatically
 *         - C-AERO holders call claimRebase() → receive NEW V+C tokens
 *      
 *      2. TRADING FEES (AERO from Aerodrome fee distributors):
 *         - collectFees() claims AERO → 50% to C holders, 50% to Meta
 *         - Non-AERO tokens: FeeSwapper converts to AERO via processSwappedFees()
 *         - C-AERO holders call claimFees() → receive AERO
 *      
 *      3. META REWARDS (from Meta contract - NOT Splitter):
 *         - CToken.collectMeta() pulls from Meta.claimForVEPool()
 *         - C-AERO holders call CToken.claimMeta() → receive META
 *      
 *      4. BRIBES (handled by VeAeroBribes):
 *         - collectBribes() claims from Aerodrome, tokens stay here
 *         - VeAeroBribes handles snapshot/claim via pullBribeToken()
 *
 * DELTA Changes from GAMMA:
 *      - Removed: collectMeta(), claimMeta(), globalMetaIndex (META never flows to Splitter)
 *      - Added: FeeSwapper integration for non-AERO fee tokens
 *      - Added: processSwappedFees() callback from FeeSwapper
 *      - Changed: onCTokenTransfer() re-indexes unclaimed fees instead of sweep to Tokenisys
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
    IRewardsDistributor public immutable REWARDS_DISTRIBUTOR;

    
    // ═══════════════════════════════════════════════════════════════
    // EXTERNAL CONTRACTS (Mutable)
    // ═══════════════════════════════════════════════════════════════
    
    IVoter public aerodromeVoter;
    IEpochGovernor public epochGovernor;
    IVoteLib public voteLib;
    IProposalVoteLib public proposalVoteLib;
    IEmissionsVoteLib public emissionsVoteLib;
    
    address public feeSwapper;

    // ═══════════════════════════════════════════════════════════════
    // NFT STATE
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public masterNftId;
    uint256[] public pendingNftIds;
    uint256 public pendingNftBlock;
    uint256[] public splitNftIds; 
    
    // ═══════════════════════════════════════════════════════════════
    // EPOCH STATE
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public currentEpoch;
    uint256 public epochEndTime;
    uint256 public votingStartTime;
    uint256 public votingEndTime;
    bool public voteExecutedThisEpoch;
    uint256 public cachedTotalVLockedForVoting;
    
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
    event NFTsConsolidated(uint256 count);
    
    // Voting events
    event GaugeVoteExecuted(address[] pools, uint256[] weights, uint256 activeTotal, uint256 passiveTotal);
    event EmissionsVoteExecuted(uint256 proposalId, uint8 support, uint256 totalVotes);
    event PoolRegistered(address indexed pool, uint256 indexed index);
    event ProposalVoteLibUpdated(address indexed newLib);
    event ProposalVoteExecuted(uint256 indexed proposalId, address indexed governor, uint8 support, uint256 weight);

    
    // Epoch events
    event EpochReset(uint256 indexed newEpoch, uint256 newEndTime);
    event VotingWindowSet(uint256 indexed epoch, uint256 votingStart, uint256 votingEnd, uint256 epochEnd);
    
    // Fee claim events
    event FeesCollected(uint256 totalAero, uint256 holderShare, uint256 metaShare, uint256 newFeeIndex);
    event FeesClaimed(address indexed user, uint256 amount);
    event FeeSwapperUpdated(address indexed newFeeSwapper);
    
    // Bribe events
    event BribeTokenWhitelisted(address indexed token, uint256 epoch);
    event BribeTokenPulled(address indexed token, address indexed to, uint256 amount);
    event BribesSwept(address indexed token, address indexed to, uint256 amount);
    event RebaseCollected(uint256 amount);
    

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
    event EmissionsVoteLibUpdated(address indexed lib);
    event MultiNFTVoteExecuted(uint256 numNfts, uint256 numPools);
    event SplitNftsMerged(uint256 count, uint256 indexed masterNftId);
   
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error ZeroAddress();
    error ZeroAmount();
    error InvalidTiming();
    error NothingToClaim();
    error Unauthorized();
    error InvalidGauge(address pool);
    error WindowClosed();
   
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
            revert InvalidTiming();
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
        if (_votingEscrow == address(0) || _aeroToken == address(0) || _metaToken == address(0) || _vToken == address(0) || _cToken == address(0) || _rToken == address(0) || _tokenisys == address(0) || _liquidationMultisig == address(0) || _liquidation == address(0) || _bribes == address(0) || _aerodromeVoter == address(0)) revert ZeroAddress();
        
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
        REWARDS_DISTRIBUTOR = IRewardsDistributor(VOTING_ESCROW.distributor());

        aerodromeVoter = IVoter(_aerodromeVoter);
        epochGovernor = IEpochGovernor(_epochGovernor);
        
        // Initialize epoch
        currentEpoch = 1;
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        globalFeeIndex = PRECISION;
        globalRebaseIndex = PRECISION;
        
        emit EpochReset(1, epochEndTime);
        emit VotingWindowSet(1, votingStartTime, votingEndTime, epochEndTime);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // EPOCH RESET
    // ═══════════════════════════════════════════════════════════════
    
    function resetEpoch() external notInLiquidation {
        if (block.timestamp < epochEndTime) revert InvalidTiming();
        _resetEpoch();
    }
    
    function _resetEpoch() internal {
        currentEpoch++;
        epochEndTime = _getNextThursday();
        votingStartTime = epochEndTime - 7 days + 1 hours;
        votingEndTime = epochEndTime - 2 hours;
        
        voteExecutedThisEpoch = false;
         if (address(emissionsVoteLib) != address(0)) {
            emissionsVoteLib.resetEpoch(currentEpoch);
        }
        
       // Collect rebase from Aerodrome (fail-safe)
        _collectRebaseInternal();       


        
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
        if (!_isDepositWindowOpen()) revert InvalidTiming();
        
        // Auto-consolidate pending NFTs from previous blocks
        // Auto-consolidate pending NFTs (only if master hasn't voted)
        if (pendingNftIds.length > 0 && 
            block.number > pendingNftBlock && 
            masterNftId != 0 &&
            !VOTING_ESCROW.voted(masterNftId)) {
            _consolidateAll();
        }
        
        if (VOTING_ESCROW.ownerOf(tokenId) != msg.sender) revert Unauthorized();
        if (VOTING_ESCROW.voted(tokenId)) revert InvalidTiming();
        
        IVotingEscrow.LockedBalance memory locked = VOTING_ESCROW.locked(tokenId);
        if (!locked.isPermanent) revert Unauthorized();
        
        uint256 lockedAmount = uint256(uint128(locked.amount));
        if (lockedAmount < MIN_DEPOSIT_AMOUNT) revert ZeroAmount();
        
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
        if (masterNftId == 0) revert NothingToClaim();
        if (pendingNftIds.length == 0) revert NothingToClaim();
        if (block.number <= pendingNftBlock) revert InvalidTiming();
        
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

    function _mergeSplitNfts() internal {
        uint256 count = splitNftIds.length;
        
        // First NFT becomes the new master
        uint256 newMaster = splitNftIds[0];
        
        // Merge all others into the first
        for (uint256 i = 1; i < count; i++) {
            VOTING_ESCROW.unlockPermanent(splitNftIds[i]);
            VOTING_ESCROW.merge(splitNftIds[i], newMaster);
        }
        
        // Update master NFT ID
        masterNftId = newMaster;
        lastTrackedLocked = uint256(uint128(VOTING_ESCROW.locked(masterNftId).amount));
        
        // Clear split tracking
        delete splitNftIds;
        
        emit SplitNftsMerged(count, masterNftId);
    }
    /**
    * @notice Reset NFT votes and merge split NFTs
    * @dev Keeper function - must wait for Aerodrome distribute window to close (Thu 01:00+)
    */
    function consolidateNFTs() external nonReentrant notInLiquidation {
        // Cannot call during Aerodrome's distribute window (Thu 00:00-01:00 UTC)
        uint256 epochStart = (block.timestamp / 1 weeks) * 1 weeks;
        uint256 timeSinceEpochStart = block.timestamp - epochStart;
        if (timeSinceEpochStart < 1 hours) revert WindowClosed();
        
        if (splitNftIds.length > 0) {
            // Reset all split NFTs
            for (uint256 i = 0; i < splitNftIds.length; i++) {
                if (VOTING_ESCROW.voted(splitNftIds[i])) {
                    aerodromeVoter.reset(splitNftIds[i]);
                }
            }
            // Merge back into master
            _mergeSplitNfts();
        } else if (masterNftId != 0 && VOTING_ESCROW.voted(masterNftId)) {
            // Normal case - just reset master
            aerodromeVoter.reset(masterNftId);
        }
        
        emit NFTsConsolidated(splitNftIds.length > 0 ? splitNftIds.length : 1);
    }


    
    // ═══════════════════════════════════════════════════════════════
    // GAUGE VOTING
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Execute gauge votes using aggregated votes from VToken
     * @dev Callable by anyone during execution window
     */
    function executeGaugeVote() external nonReentrant notInLiquidation {
    if (voteExecutedThisEpoch) revert InvalidTiming();
    if (block.timestamp <= votingEndTime) revert InvalidTiming();
    if (block.timestamp > epochEndTime) revert InvalidTiming();
    
    // Auto-consolidate pending NFTs before voting
    if (pendingNftIds.length > 0 && block.number > pendingNftBlock) {
        _consolidateAll();
    }
    
    // Get aggregated votes from VToken
    (address[] memory pools, uint256[] memory weights) = V_TOKEN.getAggregatedVotes();
    
    // Handle empty votes properly
    if (pools.length == 0) {
        // Check if there are passive votes but no active votes
        uint256 passiveVotes = V_TOKEN.totalPassiveVotes();
        if (passiveVotes > 0) {
            revert NothingToClaim();  // Can't distribute passive without active
        }
        cachedTotalVLockedForVoting = 0;
        emit GaugeVoteExecuted(pools, weights, 0, 0);
        voteExecutedThisEpoch = true;
        return;
    }
    
    // Execute vote
    bool canSplit = VOTING_ESCROW.canSplit(address(this));

    if (pools.length <= MAX_VOTE_POOLS) {
        // Direct execution (≤30 pools)
        aerodromeVoter.vote(masterNftId, pools, weights);
    } else if (canSplit && address(voteLib) != address(0)) {
        // Multi-NFT split voting (whitelisted and VoteLib set)
        _executeMultiNFTVote(pools, weights);
    } else {
        // Truncate to top 30 pools (not whitelisted)
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

    // Cache total for bribe snapshots BEFORE reset
    cachedTotalVLockedForVoting = activeVotesThisEpoch;
    
    // Reset VToken for next epoch
    V_TOKEN.resetVotesForNewEpoch();
    
    // Emit with actual totals from this epoch (both in whole tokens)
    emit GaugeVoteExecuted(pools, weights, activeVotesThisEpoch, passiveVotesThisEpoch);
    }


    function _executeMultiNFTVote(address[] memory pools, uint256[] memory weights) internal {
        // Get distribution from VoteLib
        IVoteLib.NFTVote[] memory nftVotes = voteLib.distributeVotes(pools, weights);
        
        uint256 numNFTs = nftVotes.length;
        uint256 masterBalance = uint256(uint128(VOTING_ESCROW.locked(masterNftId).amount));
        
        // Clear any previous split tracking
        delete splitNftIds;
        
        // Split master into required number of NFTs
        uint256 currentNftId = masterNftId;
        
        for (uint256 i = 0; i < numNFTs - 1; i++) {
            // Calculate split amount for next NFT
            uint256 splitAmount = (masterBalance * nftVotes[i + 1].nftWeightBps) / 10000;
            
            // Split returns (remainingNftId, newNftId)
            (uint256 remainingNftId, uint256 newNftId) = VOTING_ESCROW.split(currentNftId, splitAmount);
            
            // Track all NFTs
            if (i == 0) {
                splitNftIds.push(remainingNftId);  // First piece of original master
            }
            splitNftIds.push(newNftId);  // New split piece
            
            // Continue splitting from remaining
            currentNftId = remainingNftId;
        }
        
        // If only one split happened, add the remaining piece
        if (splitNftIds.length == 0) {
            splitNftIds.push(masterNftId);
        }
        
        // Lock all split NFTs as permanent and vote
        for (uint256 i = 0; i < splitNftIds.length; i++) {
            // Lock permanent if not already
            IVotingEscrow.LockedBalance memory locked = VOTING_ESCROW.locked(splitNftIds[i]);
            if (!locked.isPermanent) {
                VOTING_ESCROW.lockPermanent(splitNftIds[i]);
            }
            
            // Vote this NFT
            aerodromeVoter.vote(splitNftIds[i], nftVotes[i].pools, nftVotes[i].weights);
        }
        
        // Master is now invalid (was split) - will be restored on resetEpoch
        masterNftId = 0;
        
        emit MultiNFTVoteExecuted(numNFTs, pools.length);
    }

    // ═══════════════════════════════════════════════════════════════
    // EMISSIONS VOTING
    // ═══════════════════════════════════════════════════════════════
    
    function executeEmissionsVote(uint256 proposalId) external nonReentrant {
        if (address(epochGovernor) == address(0)) revert ZeroAddress();
        if (address(emissionsVoteLib) == address(0)) revert ZeroAddress();
        if (masterNftId == 0) revert NothingToClaim();
        if (block.timestamp < votingEndTime) revert InvalidTiming();
        if (block.timestamp > votingEndTime + 1 hours) revert InvalidTiming();
        
        (uint8 support, uint256 maxVotes) = emissionsVoteLib.getWinningChoice();
        
        if (maxVotes == 0) revert NothingToClaim();
        
        epochGovernor.castVote(proposalId, masterNftId, support);
        
        emit EmissionsVoteExecuted(proposalId, support, maxVotes);
    }
    
    function executeProposalVote(uint256 proposalId) external nonReentrant {
        if (address(proposalVoteLib) == address(0)) revert ZeroAddress();
        if (masterNftId == 0) revert NothingToClaim();
        
        (address governor, uint8 support, uint256 weight) = proposalVoteLib.getVoteInstruction(proposalId);
        
        if (weight == 0) revert NothingToClaim();
        
        IProtocolGovernor(governor).castVote(proposalId, masterNftId, support);
        
        emit ProposalVoteExecuted(proposalId, governor, support, weight);
    }

    // ═══════════════════════════════════════════════════════════════
    // FEE COLLECTION & CLAIMS
    // ═══════════════════════════════════════════════════════════════
    
    function collectFees(
        address[] calldata feeDistributors,
        address[][] calldata tokens
    ) external nonReentrant notInLiquidation {
        if (masterNftId == 0) revert NothingToClaim();
        
        uint256 balanceBefore = AERO_TOKEN.balanceOf(address(this));
        
        aerodromeVoter.claimFees(feeDistributors, tokens, masterNftId);
        
        // Push non-AERO tokens to FeeSwapper
        address _feeSwapper = feeSwapper;
        if (_feeSwapper != address(0)) {
            uint256 len = tokens.length;
            for (uint256 i; i < len; ) {
                uint256 tLen = tokens[i].length;
                for (uint256 j; j < tLen; ) {
                    address token = tokens[i][j];
                    if (token != address(AERO_TOKEN)) {
                        uint256 bal = IERC20(token).balanceOf(address(this));
                        if (bal > 0) {
                            IERC20(token).safeTransfer(_feeSwapper, bal);
                        }
                    }
                    unchecked { ++j; }
                }
                unchecked { ++i; }
            }
        }
        
        uint256 balanceAfter = AERO_TOKEN.balanceOf(address(this));
        uint256 collected = balanceAfter - balanceBefore;
        
        if (collected == 0) return;
        
        uint256 holderShare = collected >> 1;
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

    function processSwappedFees(uint256 amount) external {
        if (msg.sender != feeSwapper) revert Unauthorized();
        if (amount == 0) return;
        
        uint256 holderShare = amount >> 1;
        uint256 metaShare = amount - holderShare;
        
        uint256 cSupply = C_TOKEN.totalSupply();
        if (cSupply > 0) {
            globalFeeIndex += (holderShare * PRECISION) / cSupply;
        }
        
        emit FeesCollected(amount, holderShare, metaShare, globalFeeIndex);
        
        if (metaShare > 0) {
            AERO_TOKEN.approve(address(META_TOKEN), metaShare);
            IMeta(address(META_TOKEN)).receiveFees(metaShare);
        }
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

    function _collectRebaseInternal() internal {
        if (masterNftId == 0) return;
        
        // Try to claim from Aerodrome - don't revert if it fails
        try REWARDS_DISTRIBUTOR.claim(masterNftId) returns (uint256 claimed) {
            if (claimed > 0) {
                emit RebaseCollected(claimed);
            }
        } catch {
            // Aerodrome claim failed - continue anyway
        }
        
        _updateRebaseIndex();
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

    /**
    * @notice Collect rebase from Aerodrome RewardsDistributor
    * @dev Anyone can call - updates rebase index after collection
    * @return claimed Amount of AERO added to master NFT
    */
    function collectRebase() external notInLiquidation returns (uint256 claimed) {
        if (masterNftId == 0) revert NothingToClaim();
        claimed = REWARDS_DISTRIBUTOR.claim(masterNftId);
        _updateRebaseIndex();
        emit RebaseCollected(claimed);
    }

    // ═══════════════════════════════════════════════════════════════
    // TRANSFER SETTLEMENT (called by CToken)
    // ═══════════════════════════════════════════════════════════════
    
    function onCTokenTransfer(
    address from,
    address to,
    uint256 amount
) external {
    if (msg.sender != address(C_TOKEN)) revert Unauthorized();
    if (from == address(0) || to == address(0)) return;
    if (from == to) return;
    
    uint256 cSupply = C_TOKEN.totalSupply();
    
    // Re-index sender's unclaimed fees to all holders
    uint256 fromFeeCheckpoint = userFeeCheckpoint[from];
    if (fromFeeCheckpoint == 0) fromFeeCheckpoint = PRECISION;
    uint256 unclaimedFees = (amount * (globalFeeIndex - fromFeeCheckpoint)) / PRECISION;
    if (unclaimedFees > 0 && cSupply > 0) {
        globalFeeIndex += (unclaimedFees * PRECISION) / cSupply;
    }
    
    // Recipient checkpoint blending
    uint256 toBalanceAfter = C_TOKEN.balanceOf(to);
    uint256 toBalanceBefore = toBalanceAfter - amount;
    
    if (toBalanceBefore == 0) {
        userFeeCheckpoint[to] = globalFeeIndex;
        userRebaseCheckpoint[to] = globalRebaseIndex;
    } else {
        uint256 tfc = userFeeCheckpoint[to];
        if (tfc == 0) tfc = PRECISION;
        userFeeCheckpoint[to] = ((toBalanceBefore * tfc) + (amount * globalFeeIndex) + toBalanceAfter - 1) / toBalanceAfter;
        
        uint256 trc = userRebaseCheckpoint[to];
        if (trc == 0) trc = globalRebaseIndex;
        userRebaseCheckpoint[to] = ((toBalanceBefore * trc) + (amount * globalRebaseIndex) + toBalanceAfter - 1) / toBalanceAfter;
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
        if (masterNftId == 0) revert NothingToClaim();
        
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
        if (msg.sender != BRIBES) revert Unauthorized();
        
        // Cannot pull protocol tokens
        if (token == address(AERO_TOKEN)) revert Unauthorized();
        
        // Must be whitelisted for current epoch
        if (!isWhitelistedBribe[token]) revert Unauthorized();
        if (bribeWhitelistEpoch[token] != currentEpoch) revert Unauthorized();
        
        // Transfer to recipient
        IERC20(token).safeTransfer(to, amount);
        
        emit BribeTokenPulled(token, to, amount);
    }

    /**
    * @notice Sweep any tokens to designated address (Tokenisys only)
    * @dev Only callable in last hour of epoch (sweep window)
    * @param tokens Array of token addresses to sweep
    * @param to Recipient address (address(0) defaults to TOKENISYS)
    */
    function sweepBribes(address[] calldata tokens, address to) external {
        if (msg.sender != TOKENISYS) revert Unauthorized();
        
        uint256 epochEnd = epochEndTime;
        if (block.timestamp < epochEnd - 1 hours) revert WindowClosed();
        if (block.timestamp >= epochEnd) revert WindowClosed();
        
        address recipient = to == address(0) ? TOKENISYS : to;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(recipient, balance);
                emit BribesSwept(tokens[i], recipient, balance);
            }
        }
    }

    
    // ═══════════════════════════════════════════════════════════════
    // LIQUIDATION FINALIZATION (R-Token, NFT Withdrawal)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Claim R-Tokens after liquidation approved
     * @dev Users get R-Tokens proportional to their C-AERO locked
     */
    function claimRTokens() external nonReentrant {
        if (!LIQUIDATION.isLiquidationApproved()) revert InvalidTiming();
        
        uint256 approvedTime = LIQUIDATION.getLiquidationApprovedTime();
        if (block.timestamp > approvedTime + R_CLAIM_WINDOW) revert WindowClosed();
        
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
        if (msg.sender != owner() && msg.sender != LIQUIDATION_MULTISIG) revert Unauthorized();
        if (!LIQUIDATION.isLiquidationApproved()) revert InvalidTiming();
        
        uint256 approvedTime = LIQUIDATION.getLiquidationApprovedTime();
        if (block.timestamp <= approvedTime + R_CLAIM_WINDOW) revert WindowClosed();
        
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
        if (msg.sender != LIQUIDATION_MULTISIG) revert Unauthorized();
        
        (IVeAeroLiquidation.LiquidationPhase phase,,,,, ) = 
            LIQUIDATION.getLiquidationStatus(currentEpoch, epochEndTime);
        
        if (phase != IVeAeroLiquidation.LiquidationPhase.Closed) {
            revert InvalidTiming();
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
    function setProposalVoteLib(address _lib) external onlyOwner {
        proposalVoteLib = IProposalVoteLib(_lib);
        emit ProposalVoteLibUpdated(_lib);
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
    /**
     * @notice Set EmissionsVoteLib address
     * @param _lib EmissionsVoteLib contract address
     */
    function setEmissionsVoteLib(address _lib) external onlyOwner {
        emissionsVoteLib = IEmissionsVoteLib(_lib);
        emit EmissionsVoteLibUpdated(_lib);
    }

    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    
    /**
     * @notice Check if liquidation is active (for VeAeroBribes)
     */
    function isLiquidationActive() external view returns (bool) {
        return LIQUIDATION.isLiquidationApproved();
    }
    
    // ═══════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════

    function setFeeSwapper(address _feeSwapper) external onlyOwner {
        feeSwapper = _feeSwapper;
        emit FeeSwapperUpdated(_feeSwapper);
    }
    
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

    /**
     * @notice Get current active votes (computed dynamically)
     * @return Active votes in whole tokens
     */
    function totalVLockedForVoting() public view returns (uint256) {
        return V_TOKEN.totalGaugeVotedThisEpoch() / 1e18;
    }

}