// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title Interfaces V.BETA.1
 * @notice Centralized interface definitions for VeAero Ecosystem
 */

// ═══════════════════════════════════════════════════════════════════════════
// PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IVeAeroSplitter
 * @notice Interface for VeAeroSplitter BETA.1 tokens
 */
interface IVeAeroSplitter {
    // Gauge voting
    function executeGaugeVote() external;
    
    // Liquidation (called by CToken and VToken)
    function recordCLock(address user, uint256 amount) external;
    function recordVConfirmation(address user, uint256 amount) external;
    
    // Timing (used by VToken and CToken for voting windows)
    function votingStartTime() external view returns (uint256);
    function votingEndTime() external view returns (uint256);
    function epochEndTime() external view returns (uint256);
    function currentEpoch() external view returns (uint256);
    
    // Liquidation phase
    function liquidationPhase() external view returns (uint8);
    
    // Total V locked for bribe snapshot
    function totalVLockedForVoting() external view returns (uint256);

    function isValidGauge(address pool) external view returns (bool);
    
    // Transfer settlement (called by CToken._update)
    // Settles sender's rewards to treasury, weighted checkpoint for receiver
    function onCTokenTransfer(address from, address to, uint256 amount) external;
}

/**
 * @title IVToken
 * @notice Interface for V-AERO token
 */
interface IVToken {
    // Minting/burning (called by VeAeroSplitter)
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    
    // ERC20 views
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    
    // Lock state
    function lockedAmount(address account) external view returns (uint256);
    function lockedUntil(address account) external view returns (uint256);
    
    // Voting (called by Meta for V-AERO voting)
    function vote(address pool, uint256 amount) external;
    function votePassive(uint256 amount) external;

    // Vote aggregation
    function getAggregatedVotes() external view returns (
        address[] memory pools,
        uint256[] memory weights
    );
    
    // Epoch reset
    function resetVotesForNewEpoch() external;
    
    // View functions
    function getTotalVotedPools() external view returns (uint256);
    function getPoolVotes(address pool) external view returns (uint256);
    function totalPassiveVotes() external view returns (uint256);
    function weightsEpoch() external view returns (uint256);
    function currentLockedAmount(address user) external view returns (uint256);
    
    // Admin
    function configureVotingStorage(uint256 maxPools, uint256 totalSupply) external;
    
    // Existing functions
    function unlockedBalanceOf(address account) external view returns (uint256);
    function totalGaugeVotedThisEpoch() external view returns (uint256);
}


/**
 * @title ICToken
 * @notice Interface for C-AERO token
 */
interface ICToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title IRToken
 * @notice Interface for R-AERO token (liquidation receipts)
 */
interface IRToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title IMeta
 * @notice Interface for META token
 */
interface IMeta {
    // Fee receiving from VeAeroSplitter
    function receiveFees(uint256 amount) external;
    
    // Index updates (used by CToken)
    function needsIndexUpdate() external view returns (bool);
    function lastUpdateDay() external view returns (uint64);
    // Note: updateIndex() returns (uint64 processedDays, bool complete)
    function updateIndex() external returns (uint64, bool);
    
    // VE Pool claims (used by CToken)
    function claimForVEPool() external returns (uint256);
    
    // Added chainId to match Meta.sol implementation
    function getPoolInfo(address vePool) external view returns (
        bool whitelisted,
        uint256 votes,
        uint256 pendingRewards,
        uint256 chainId  // ← ADDED: Was missing in original
    );
    
    // Staking
    function lockAndVote(uint256 amount, address vePool) external;
    function initiateUnlock() external;
    function completeUnlock() external;
    
    // LP gauge
    function pushToLPGauge() external;
    function pushVote() external;
    
    // Views
    function getCurrentS() external view returns (uint256);
    function totalLockedVotes() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    // fee payout to C token
    function claimFeesForVEPool() external returns (uint256);
    function poolFeeAccrued(address pool) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════
// AERODROME EXTERNAL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IVotingEscrow
 * @notice Interface for Aerodrome VotingEscrow (veAERO)
 */
interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }
    
    function ownerOf(uint256 tokenId) external view returns (address);
    function voted(uint256 tokenId) external view returns (bool);
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function unlockPermanent(uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function depositFor(uint256 tokenId, uint256 amount) external;
    function split(uint256 _from, uint256 _amount) external returns (uint256 _tokenId1, uint256 _tokenId2);
    function canSplit(address _account) external view returns (bool);
    function lockPermanent(uint256 _tokenId) external;
    function distributor() external view returns (address);
}

/**
 * @title IVoter
 * @notice Interface for Aerodrome Voter
 */
interface IVoter {
    function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata weights) external;
    function claimFees(address[] calldata fees, address[][] calldata tokens, uint256 tokenId) external;
    function claimBribes(address[] calldata bribes, address[][] calldata tokens, uint256 tokenId) external;
    function gauges(address pool) external view returns (address);
    function isGauge(address gauge) external view returns (bool);
    function isAlive(address gauge) external view returns (bool);
    function length() external view returns (uint256);
    function reset(uint256 _tokenId) external;
}

/**
 * @title IRewardsDistributor
 * @notice Interface for Aerodrome RewardsDistributor (veAERO rebases)
 */
interface IRewardsDistributor {
    function claim(uint256 _tokenId) external returns (uint256);
}

/**
 * @title IEpochGovernor
 * @notice Interface for Aerodrome EpochGovernor
 */
interface IEpochGovernor {
    function castVote(uint256 proposalId, uint256 tokenId, uint8 support) external returns (uint256);
}

/**
 * @title IGauge
 * @notice Interface for Aerodrome Gauge (LP staking)
 */
interface IGauge {
    function notifyRewardAmount(address token, uint256 amount) external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSS-CHAIN INTERFACES (V7)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IL1ProofVerifier
 * @notice Interface for L1 state proof verification
 */
interface IL1ProofVerifier {
    function verifyRemoteFees(
        uint256 chainId,
        uint256 epoch,
        uint256 totalFees,
        bytes calldata proof
    ) external view returns (bool);
    
    function verifyRemoteBurn(
        uint256 chainId,
        address user,
        uint256 burnedAmount,
        bytes calldata proof
    ) external view returns (bool);
}

/**
 * @title IVeAeroLiquidation
 * @notice Interface for VeAeroLiquidation contract 
 */
interface IVeAeroLiquidation {
    // Enum must be declared in interface for return type
    enum LiquidationPhase { Normal, CLock, CVote, VConfirm, Approved, Closed }
    
    // Called by CToken/VToken
    function recordCLock(address user, uint256 amount) external;
    function recordVConfirmation(address user, uint256 amount) external;
    
    // Called by anyone (phase resolution)
    function resolveCVote(uint256 currentEpoch) external;
    function resolveVConfirm(uint256 currentEpoch) external;
    
    // Called by users (after failed liquidation)
    function withdrawFailedLiquidation() external;
    
    // Called by Splitter only
    function markClosed() external;
    
    // View functions
    function liquidationPhase() external view returns (LiquidationPhase);
    function isLiquidationApproved() external view returns (bool);
    function getLiquidationApprovedTime() external view returns (uint256);
    function getUserCLocked(address user) external view returns (uint256);
    function getTotalCLocked() external view returns (uint256);
    function getLiquidationStatus(
        uint256 currentEpoch,
        uint256 epochEndTime
    ) external view returns (
        LiquidationPhase phase,
        uint256 cLockedPercent,
        uint256 vLockedPercent,
        uint256 cTargetPercent,
        uint256 vTargetPercent,
        uint256 timeRemaining
    );
    function daysRemainingInCVote() external view returns (uint256);
}

/**
 * @title IProposalVoteLib
 * @notice Interface for proposal vote aggregation (deployed by MSIG when needed)
 */
interface IProposalVoteLib {
    function getVoteInstruction(uint256 proposalId) external view returns (
        address governor,
        uint8 support,
        uint256 weight
    );
}

/**
 * @title IProtocolGovernor  
 * @notice Interface for Aerodrome/OpenZeppelin Governor
 */
interface IProtocolGovernor {
    function castVote(uint256 proposalId, uint256 tokenId, uint8 support) external returns (uint256);
    function proposalDeadline(uint256 proposalId) external view returns (uint256);
}

/**
 * @title IEmissionsVoteLib
 * @notice Interface for EmissionsVoteLib - emissions voting logic extracted from Splitter
 */
interface IEmissionsVoteLib {
    /// @notice Record an emissions vote (called by CToken)
    function recordVote(address user, int8 choice, uint256 amount) external;
    
    /// @notice Reset vote totals for new epoch (called by Splitter)
    function resetEpoch(uint256 newEpoch) external;
    
    /// @notice Get the winning choice for execution
    /// @return support 0=Against, 1=Abstain, 2=For
    /// @return maxVotes The winning vote total
    function getWinningChoice() external view returns (uint8 support, uint256 maxVotes);
    
    /// @notice Get all vote totals
    function getTotals() external view returns (uint256 decrease, uint256 hold, uint256 increase);
    
    /// @notice Current epoch
    function currentEpoch() external view returns (uint256);
}

